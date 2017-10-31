class Broadcast::ItemsController < ApplicationController
  before_action :check_access, except: [:scripts, :view_script]
  before_action :set_item, only: [:added, :edit, :update, :add_translation, :submit_translation, :deprecate_item, :item_review, :submit_review]

  def index
    @language = Translations::Language[params[:lang] || 'en-US']
    @items = if params[:match].present?
               Broadcast::Item.active.search(params[:match]).includes(:municipality, translations: [:source_lang, :target_lang])
             else
               Broadcast::Item.active.includes(:municipality, translations: [:source_lang, :target_lang])
             end
    @items = conditional_filter @items, originated_at: params[:originated_at], broadcast_municipality_id: params[:municipality],
                                        source: params[:source], id: params[:id]
    @items = @items.order(originated_at: :desc).paginate page: params[:page], per_page: 100
  end

  def new
    @item = Broadcast::Item.new
  end

  def create
    @item = Broadcast::Item.new item_params.merge(user: current_user)
    if (!params[:content].nil? || !params[:translation].nil?) && @item.save
      now = DateTime.now.utc
      if now.hour >= 0 && now.hour < 14
        now = now.change(hour: 14)
      elsif now.hour >= 14
        now = (now + 1.day).change(hour: 0)
      end
      if params[:translation].empty?
        from = Translations::Language['en-US']
        to = Translations::Language['es-PR']
        content = params[:content]
      elsif params[:content].empty?
        from = Translations::Language['es-PR']
        to = Translations::Language['en-US']
        content = params[:translation]
      else
        from = Translations::Language['en-US']
        to = Translations::Language['es-PR']
        content = params[:content]
        final = params[:translation]
        status = Translations::Status['Completed']
      end
      @item.translations.create(content: content, source_lang: from, target_lang: to, deliver_to: 'SCOT', due: now,
                                requester: current_user, priority: Translations::Priority['Next Broadcast'], final: final, status: status)
      flash[:success] = 'Entry submitted to broadcast list.'
      redirect_to added_broadcast_item_path(@item)
    else
      flash[:danger] = 'Failed to save broadcast item. This could be because you left both english and spanish blank, or a different issue.'
      render :new
    end
  end

  def edit; end

  def update
    success = ActiveRecord::Base.transaction do
      @item.update(item_params)
      @item.translations.first.update(status: Translations::Status['Edited'], assignee: nil,
                                      **params[:translation].permit(:content, :final, :source_lang_id, :target_lang_id).to_h.symbolize_keys)
    end
    if success
      hash = @item.municipality.present? ? "#{@item.municipality&.name&.downcase&.tr(' ', '_')}_eng" : nil
      script_params = params[:broadcast_item][:script]&.permit(:name, :max_general, :max_muni, :min_origin)
      redirect_to added_broadcast_item_path(@item, h: hash, sc: script_params)
    else
      render :edit
    end
  end

  def added
    @panda = Rails.cache.fetch :panda, expires_in: 5.minutes do
      panda_req = HTTParty.get("https://api.giphy.com/v1/gifs/random?key=#{Settings.giphy_api_key}&tag=panda")
      JSON.parse(panda_req.body)['data']['image_url'] if panda_req.code == 200
    end
  end

  def need_translation
    @items = Broadcast::Item.active.where("translation IS NULL OR translation = ''").order(originated_at: :desc)
                            .paginate(page: params[:page], per_page: 100)
  end

  def add_translation; end

  def submit_translation
    if @item.update translation: params[:translation]
      if @item.request.present?
        status = Translations::Status['Completed']
        @item.request.update(status: status, assignee: current_user)
      end
      redirect_to added_broadcast_item_path(@item, t: 0, tn: 1)
    else
      render :add_translation
    end
  end

  def setup_generation; end

  def generate_script
    @broadcasts = Broadcast::Item.generate_script(params.dup.permit(:name, :max_general, :max_muni, :min_origin).to_h)
  end

  def deprecate_item
    @item.update(deprecated: true)
    flash[:success] = 'Marked item as deprecated.'
    redirect_back fallback_location: broadcast_items_path
  end

  def scripts
    @files = Dir[Rails.root.join('data', '*.yml')].map { |f| [File.basename(f, '.yml'), 'yml'] } +
             Dir[Rails.root.join('data', '*.html')].map { |f| [File.basename(f, '.html'), 'html'] }.sort_by!(&:first).reverse
  end

  def view_script
    if params[:format] == 'html'
      @document = File.read(Rails.root.join('data', "#{params[:file].tr('/', '')}.html")).split("\n")
      render :generate_html_script
    else
      @broadcasts = YAML.load_file(Rails.root.join('data', "#{params[:file].tr('/', '')}.yml"))
      render :generate_script, formats: [:html, :erb]
    end
  end

  def review
    @items = Broadcast::Item.active.with_assoc.where(status: Broadcast::Status['Pending Review']).order(id: :desc)
  end

  def item_review
    @translation = @item.translations.first
  end

  def submit_review
    @translation = @item.translations.first
    orig = { content: @translation.content, final: @translation.final }
    status = case @translation.status
             when Translations::Status['Completed']
               Broadcast::Status['Finalized']
             when Translations::Status['Pending Review']
               Broadcast::Status['Translated']
             else
               Broadcast::Status['Pending Translation']
             end
    success = ActiveRecord::Base.transaction do
      @item.update status: status
      @translation.update params.require(:translation).permit(:content, :final)
      if @translation.final != orig[:final] || @translation.content != orig[:content]
        @translation.update status: Translations::Status['Edited']
      end
    end
    if success
      flash[:success] = 'Marked item review complete.'
      redirect_to review_broadcast_items_path
    else
      flash[:danger] = 'Failed to complete review.'
      render :item_review
    end
  end

  private

  def check_access
    require_any :developer, :admin, :broadcast, :miner
  end

  def item_params
    params.require(:broadcast_item).permit(:content, :originated_at, :broadcast_municipality_id, :translation, :source, :top, :bottom, :notes)
  end

  def set_item
    @item = Broadcast::Item.find params[:id]
  end

  def conditional_filter(col, **filters)
    cols = Broadcast::Item.columns.map { |c| [c.name.to_sym, c] }.to_h
    types = filters.keys.reject { |k| filters[k].nil? }.map { |k| [k, cols[k].sql_type_metadata.type] }.to_h
    filters.each do |k, v|
      next unless v.present?
      col = if [:string, :text].include? types[k]
              col.where("#{k} LIKE ?", "%#{v}%")
            else
              col.where(k => v)
            end
    end
    col
  end
end
