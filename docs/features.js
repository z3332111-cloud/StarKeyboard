
(function () {
  "use strict";
  var catalog = document.getElementById("features");
  if (!catalog) return;
  var groups = Array.from(catalog.querySelectorAll("details.feature-group"));
  catalog.querySelector(".catalog-controls").hidden = false;
  document.getElementById("features-expand").addEventListener("click", function () {
    groups.forEach(function (group) { group.open = true; });
  });
  document.getElementById("features-collapse").addEventListener("click", function () {
    groups.forEach(function (group) { group.open = false; });
  });
  function openLinkedGroup() {
    var id;
    try { id = decodeURIComponent(location.hash.slice(1)); } catch (_) { return; }
    var target = document.getElementById(id);
    if (!target || !catalog.contains(target)) return;
    var group = target.closest("details.feature-group");
    if (group) group.open = true;
  }
  window.addEventListener("hashchange", openLinkedGroup);
  openLinkedGroup();
})();
