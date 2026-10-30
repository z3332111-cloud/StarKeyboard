/* Only published releases with a real installer can become download buttons. */
(function () {
  "use strict";
  var base = "https://github.com/z3332111-cloud/StarKeyboard/releases/";
  function pick(releases, prefix, filename) {
    return releases.filter(function (release) {
      return !release.draft && !release.prerelease &&
        new RegExp("^" + prefix + "[0-9]+$").test(release.tag_name) &&
        Array.isArray(release.assets) && release.assets.some(function (asset) {
          return asset.name === filename && asset.size > 0 &&
            asset.browser_download_url === base + "download/" + release.tag_name + "/" + filename;
        });
    }).sort(function (a, b) {
      return Number(b.tag_name.slice(prefix.length)) - Number(a.tag_name.slice(prefix.length));
    })[0];
  }
  function apply(releases, platform, prefix, filename) {
    var release = pick(releases, prefix, filename);
    if (!release) return;
    document.getElementById("download-" + platform).href = base + "download/" + release.tag_name + "/" + filename;
    document.getElementById("release-" + platform).href = base + "tag/" + release.tag_name;
    var version = String(release.name || "").match(/\bv(\d+\.\d+\.\d+)\b/);
    document.getElementById("version-" + platform).textContent = version ? "最新已發布：v" + version[1] : "最新版本已發布";
  }
  fetch("https://api.github.com/repos/z3332111-cloud/StarKeyboard/releases?per_page=100", {
    headers: { Accept: "application/vnd.github+json" }, cache: "no-store"
  }).then(function (response) {
    if (!response.ok) throw new Error("Release lookup unavailable");
    return response.json();
  }).then(function (releases) {
    if (!Array.isArray(releases)) return;
    apply(releases, "iphone", "build-", "StarKeyboard.ipa");
    apply(releases, "android", "android-", "StarKeyboard.apk");
  }).catch(function () {
    // Keep the verified download links in the HTML when offline or rate limited.
  });
})();
