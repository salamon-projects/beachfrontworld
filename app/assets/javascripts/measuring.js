// Keeps a landmark page that is waiting for its walks to be measured up to
// date without reloading it (which would lose the scroll position): fetches
// the page again every few seconds and swaps in the [data-measuring] block,
// and reloads once measuring is over. Without JS a <noscript> meta refresh
// reloads the page instead.
(function () {
  var block = document.querySelector("[data-measuring]");
  if (!block || !window.fetch || !window.DOMParser) return;

  var delay = (parseInt(block.getAttribute("data-measuring"), 10) || 4) * 1000;

  function poll() {
    fetch(window.location.href, { credentials: "same-origin", headers: { Accept: "text/html" } })
      .then(function (response) { return response.text(); })
      .then(function (html) {
        var next = new DOMParser().parseFromString(html, "text/html").querySelector("[data-measuring]");
        if (!next) {
          window.location.reload();
          return;
        }
        block.innerHTML = next.innerHTML;
        window.setTimeout(poll, delay);
      })
      .catch(function () { window.setTimeout(poll, delay * 2); });
  }

  window.setTimeout(poll, delay);
})();
