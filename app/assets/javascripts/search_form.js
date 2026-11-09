// The home page search card: a searchable destination list, and a check
// that every child has an age before searching. Progressive enhancement:
// without JavaScript the plain select and fields stay, and both versions
// submit the same parameters.
(function () {
  "use strict";

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  // Case- and accent-insensitive, so "porec" finds "Poreč".
  function fold(text) {
    return (text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
  }

  function format(template, values) {
    return template.replace(/%\{(\w+)\}/g, function (_, key) { return values[key]; });
  }

  // Closes a popup on a click outside it, on Escape, and when focus leaves.
  function dismissable(root, close) {
    document.addEventListener("mousedown", function (event) {
      if (!root.contains(event.target)) close(false);
    });
    root.addEventListener("keydown", function (event) {
      if (event.key === "Escape") { event.preventDefault(); close(true); }
    });
    root.addEventListener("focusout", function (event) {
      if (event.relatedTarget && !root.contains(event.relatedTarget)) close(false);
    });
  }

  // --- Destination ---------------------------------------------------------

  function DestinationPicker(form, select, labels) {
    var self = this;
    this.form = form;
    this.select = select;
    this.labels = labels;
    this.field = select.closest(".field");
    this.options = Array.prototype.filter.call(select.options, function (option) { return option.value; })
      .map(function (option) {
        return {
          value: option.value,
          name: option.textContent,
          country: option.parentNode.label || "",
          sea: option.getAttribute("data-sea") || "",
          count: parseInt(option.getAttribute("data-count"), 10) || 0
        };
      });

    this.input = el("input", "destination-picker__input");
    this.input.type = "text";
    this.input.id = select.id;
    this.input.autocomplete = "off";
    this.input.spellcheck = false;
    this.input.placeholder = labels.where_to;
    this.input.setAttribute("role", "combobox");
    this.input.setAttribute("aria-autocomplete", "list");
    this.input.setAttribute("aria-expanded", "false");
    this.input.setAttribute("aria-controls", select.id + "_list");
    select.id = select.id + "_value";
    select.hidden = true;
    select.required = false;

    this.list = el("ul", "destination-picker__list");
    this.list.id = this.input.getAttribute("aria-controls");
    this.list.setAttribute("role", "listbox");
    this.list.setAttribute("aria-label", labels.where_to);
    this.list.tabIndex = -1;
    this.list.hidden = true;

    this.clearButton = el("button", "destination-picker__clear");
    this.clearButton.type = "button";
    this.clearButton.setAttribute("aria-label", labels.clear_destination);

    this.error = el("p", "destination-picker__error", labels.required);
    this.error.id = select.id + "_error";
    this.error.hidden = true;

    var box = el("div", "destination-picker");
    box.appendChild(this.input);
    box.appendChild(this.clearButton);
    box.appendChild(this.list);
    select.parentNode.insertBefore(box, select.nextSibling);
    this.field.appendChild(this.error);
    this.field.classList.add("field--enhanced");

    var current = this.find(select.value);
    this.input.value = current ? current.name : "";
    this.refreshClear();

    this.input.addEventListener("focus", function () {
      self.input.select();
      if (!self.quietFocus) self.open();
      self.quietFocus = false;
    });
    this.input.addEventListener("click", function () { self.open(); });
    this.input.addEventListener("input", function () {
      self.showError(false);
      self.active = 0;
      self.open();
      self.refreshClear();
    });
    this.input.addEventListener("keydown", this.keydown.bind(this));
    this.list.addEventListener("mousedown", function (event) { event.preventDefault(); });
    this.list.addEventListener("click", function (event) {
      var item = event.target.closest("[role=option]");
      if (item) self.choose(self.find(item.getAttribute("data-value")));
    });
    this.clearButton.addEventListener("click", function () {
      self.input.value = "";
      self.select.value = "";
      self.refreshClear();
      self.input.focus();
    });
    form.addEventListener("submit", function (event) {
      if (self.select.value) return;
      event.preventDefault();
      self.showError(true);
      // Focus without opening the list, so the message stays readable.
      self.quietFocus = true;
      self.input.focus();
    });
    dismissable(box, function () { self.close(); });
  }

  DestinationPicker.prototype.find = function (value) {
    for (var i = 0; i < this.options.length; i++) if (this.options[i].value === value) return this.options[i];
    return null;
  };

  // Typing filters by name, country or sea; showing the chosen name lists all.
  DestinationPicker.prototype.matches = function () {
    var chosen = this.find(this.select.value);
    var query = fold(chosen && this.input.value === chosen.name ? "" : this.input.value);
    if (!query) return this.options;
    return this.options.filter(function (option) {
      return fold(option.name + " " + option.country + " " + option.sea).indexOf(query) !== -1;
    });
  };

  DestinationPicker.prototype.open = function () {
    var self = this;
    var items = this.matches();
    this.shown = items;
    if (this.active == null || this.active >= items.length) this.active = 0;
    this.list.textContent = "";

    if (!items.length) {
      var empty = el("li", "destination-picker__empty", format(this.labels.no_results, { query: this.input.value.trim() }));
      empty.setAttribute("role", "presentation");
      this.list.appendChild(empty);
    }

    var country = null;
    items.forEach(function (option, index) {
      if (option.country !== country) {
        country = option.country;
        var heading = el("li", "destination-picker__group", country);
        heading.setAttribute("role", "presentation");
        self.list.appendChild(heading);
      }
      var item = el("li", "destination-picker__option");
      item.id = self.list.id + "_" + index;
      item.setAttribute("role", "option");
      item.setAttribute("data-value", option.value);
      item.setAttribute("aria-selected", option.value === self.select.value ? "true" : "false");
      var text = el("span", "destination-picker__text");
      text.appendChild(el("span", "destination-picker__name", option.name));
      text.appendChild(el("span", "destination-picker__meta", [ option.country, option.sea ].filter(Boolean).join(" · ")));
      item.appendChild(el("span", "destination-picker__icon"));
      item.appendChild(text);
      if (option.count > 0) {
        var stays = option.count === 1 ? self.labels.stays.one : self.labels.stays.other;
        item.appendChild(el("span", "destination-picker__count", format(stays, { count: option.count })));
      }
      self.list.appendChild(item);
    });

    this.list.hidden = false;
    this.input.setAttribute("aria-expanded", "true");
    this.highlight();
  };

  DestinationPicker.prototype.close = function () {
    if (this.list.hidden) return;
    this.list.hidden = true;
    this.input.setAttribute("aria-expanded", "false");
    this.input.removeAttribute("aria-activedescendant");
    // Unfinished typing falls back to the chosen destination.
    var chosen = this.find(this.select.value);
    this.input.value = chosen ? chosen.name : "";
    this.refreshClear();
  };

  DestinationPicker.prototype.highlight = function () {
    var self = this;
    var options = this.list.querySelectorAll("[role=option]");
    Array.prototype.forEach.call(options, function (item, index) {
      item.classList.toggle("is-active", index === self.active);
    });
    var current = options[this.active];
    if (current) {
      this.input.setAttribute("aria-activedescendant", current.id);
      var top = current.offsetTop, bottom = top + current.offsetHeight;
      if (top < this.list.scrollTop) this.list.scrollTop = top - 32;
      else if (bottom > this.list.scrollTop + this.list.clientHeight) this.list.scrollTop = bottom - this.list.clientHeight;
    } else {
      this.input.removeAttribute("aria-activedescendant");
    }
  };

  DestinationPicker.prototype.keydown = function (event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (this.list.hidden) return this.open();
      var count = this.shown.length;
      if (!count) return;
      this.active = (this.active + (event.key === "ArrowDown" ? 1 : -1) + count) % count;
      this.highlight();
    } else if (event.key === "Enter") {
      if (this.list.hidden) return;
      event.preventDefault();
      if (this.shown[this.active]) this.choose(this.shown[this.active]);
    } else if (event.key === "Tab" && !this.list.hidden && this.input.value.trim() && this.shown[this.active]) {
      this.choose(this.shown[this.active], true);
    }
  };

  // Like booking sites, choosing a place moves straight on to the dates.
  DestinationPicker.prototype.choose = function (option, keepFocus) {
    if (!option) return;
    this.select.value = option.value;
    this.select.dispatchEvent(new Event("change", { bubbles: true }));
    this.input.value = option.name;
    this.showError(false);
    this.close();
    if (keepFocus) return;
    var dates = this.form.querySelector(".date-trigger");
    var checkIn = this.form.querySelector('input[name="check_in"]');
    if (dates && checkIn && !checkIn.value) dates.click();
    else if (dates) dates.focus();
  };

  DestinationPicker.prototype.showError = function (shown) {
    this.error.hidden = !shown;
    this.field.classList.toggle("has-error", shown);
    if (shown) this.input.setAttribute("aria-describedby", this.error.id);
    else this.input.removeAttribute("aria-describedby");
  };

  DestinationPicker.prototype.refreshClear = function () {
    this.clearButton.hidden = !this.input.value;
  };

  // --- Child ages --------------------------------------------------------

  // A missing child age would only fail on the server; ask for it here.
  function requireChildAges(form, labels) {
    var children = form.querySelector('select[name="children"]');
    var ages = form.querySelector(".child-ages");
    if (!children || !ages) return;
    var note = el("p", "child-ages__note", labels.ages_needed);
    // Last in the DOM so the CSS that shows one age field per child (by
    // position) still counts right; .child-ages__note puts it first.
    ages.appendChild(note);

    form.addEventListener("submit", function (event) {
      var count = parseInt(children.value, 10) || 0;
      var selects = ages.querySelectorAll("select");
      for (var i = 0; i < count && i < selects.length; i++) {
        if (!selects[i].value) {
          event.preventDefault();
          note.classList.add("is-error");
          selects[i].focus();
          return;
        }
      }
    });
    ages.addEventListener("change", function () { note.classList.remove("is-error"); });
  }

  document.addEventListener("DOMContentLoaded", function () {
    Array.prototype.forEach.call(document.querySelectorAll("form[data-search-form]"), function (form) {
      var labels = JSON.parse(form.getAttribute("data-search-form"));
      var select = form.querySelector('select[name="destination"]');
      if (select) new DestinationPicker(form, select, labels);
      requireChildAges(form, labels);
    });
  });
})();
