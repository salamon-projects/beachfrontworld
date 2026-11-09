// Home page destinations: country buttons that show one country's coasts at
// a time. Without JavaScript every country is listed under its heading.
(function () {
  "use strict";

  document.addEventListener("DOMContentLoaded", function () {
    var tabs = document.querySelector(".country-tabs");
    if (!tabs) return;
    var buttons = tabs.querySelectorAll(".country-tab");
    var groups = document.querySelectorAll(".coast-group[data-country]");

    function show(code) {
      Array.prototype.forEach.call(buttons, function (button) {
        button.setAttribute("aria-pressed", String(button.getAttribute("data-country") === code));
      });
      Array.prototype.forEach.call(groups, function (group) {
        group.hidden = group.getAttribute("data-country") !== code;
      });
    }

    tabs.hidden = false;
    document.documentElement.classList.add("has-country-tabs");
    tabs.addEventListener("click", function (event) {
      var button = event.target.closest(".country-tab");
      if (button) show(button.getAttribute("data-country"));
    });
    show(buttons[0].getAttribute("data-country"));
  });
})();
