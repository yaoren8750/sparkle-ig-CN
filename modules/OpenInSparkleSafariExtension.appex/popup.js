// The extension's two settings. Keys match content.js.
(function () {
    "use strict";

    var KEYS = ["banner", "auto"];

    KEYS.forEach(function (key) {
        var box = document.getElementById(key);
        box.addEventListener("change", function () {
            var change = {};
            change[key] = box.checked;
            browser.storage.local.set(change);
        });
    });

    browser.storage.local.get(KEYS).then(function (stored) {
        KEYS.forEach(function (key) {
            // Both are on until the user turns them off.
            document.getElementById(key).checked = stored[key] !== false;
        });
    });
})();
