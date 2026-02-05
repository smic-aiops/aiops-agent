(function () {
  function init() {
    var root = document.querySelector('.itsm-home');
    if (!root || !document.body) {
      return;
    }

    document.body.classList.add('itsm-homepage');
    window.requestAnimationFrame(function () {
      document.body.classList.add('itsm-loaded');
    });

    var selectors = [
      '.itsm-panel',
      '.itsm-flow__step',
      '.itsm-board__row',
      '.itsm-capabilities__list > div',
      '.itsm-stat'
    ];

    var targets = root.querySelectorAll(selectors.join(','));
    if (!targets.length) {
      return;
    }

    targets.forEach(function (el, index) {
      el.classList.add('itsm-reveal');
      el.style.transitionDelay = String((index % 6) * 80) + 'ms';
    });

    if (!('IntersectionObserver' in window)) {
      targets.forEach(function (el) {
        el.classList.add('is-revealed');
      });
      return;
    }

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-revealed');
            observer.unobserve(entry.target);
          }
        });
      },
      {threshold: 0.2}
    );

    targets.forEach(function (el) {
      observer.observe(el);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
