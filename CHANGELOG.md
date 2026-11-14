# Changelog

## 2.0.0 beta 3

- **Open file** button when a download finishes, and on each history entry.
- **Fixed:** Chromium refused to load the extension (`background.scripts` is not allowed there). Firefox and Chromium now have their own manifest; Chromium browsers load the `extension-chromium` folder that `install.bat` makes.
- **Fixed:** the "Take login from" dropdown was white on white in Chromium browsers.
- Firefox no longer shows manifest warnings.
- Folders tidied: the tests now live in `tools/`.

## 2.0.0 beta 2

- **Chromium support.** Works in Chrome, Edge, Brave (and should in Vivaldi/Opera) as well as Firefox. The extension is Manifest V3. Chromium browsers load the `extension-chromium` folder, which `install.bat` makes from `extension/` with `manifest.chromium.json` swapped in. The installer registers the helper for every supported browser.
- **Fixed:** the update button offering "the same version" and then failing. yt-dlp and ffmpeg are only offered when really newer than the installed file; if winget refuses, the helper tries yt-dlp's own updater and shows what winget actually said.
- "Use my browser login" now takes cookies from the browser you pick (or the one you are using).
- Update checker understands beta numbers (beta 2 -> beta 3 -> final).
- The job list survives the browser sleeping the extension (Chromium); an update check also runs on a timer alarm.
