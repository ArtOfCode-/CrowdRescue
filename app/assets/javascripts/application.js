// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, or any plugin's
// vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file. JavaScript code in this file should be added after the last require_* statement.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require rails-ujs
//= require_tree .

window.scot = {
  copy: function (elId) {
    var el = $(elId);
    el.show();
    el.select();
    var success = document.execCommand('copy');
    if (success) {
      el.hide();
    }
  },

  formatItem: function (item) {
    if (!item.id) {
      return item.content;
    }

    var text = item.content.substr(0, 100);
    if (text.length === 100) {
      text = text + '...';
    }

    return $(
      '<div><strong>#' + item.id + '</strong><br/>' + text + '</div>'
    );
  }
};

$(document).ready(function() {
  $('.slide-body').hide();

  $('.slide-header').on('click', function() {
    $(this).siblings('.slide-body').slideToggle(250);
  });

  $('.select2').select2({
    theme: 'bootstrap'
  });

  $('.select2-dedupe').select2({
    theme: 'bootstrap',
    ajax: {
      url: '/translations/dedupe/data',
      dataType: 'json'
    },
    templateResult: scot.formatItem,
    minimumInputLength: 1
  });

  date = $('.datepicker').val();

  if (date === null) {
    date = new Date();
  }

  new Pikaday({
    field: $('.datepicker')[0],
    showTime: true,
    showSeconds: false,
    use24hour: true,
    defaultDate: date,
    setDefaultDate: true,
    toString: function (date, format) {
      return date.toISOString();
    },
    onOpen: function () {
      $('.pika-time .pika-select').addClass('form-control');
    }
  });
});
