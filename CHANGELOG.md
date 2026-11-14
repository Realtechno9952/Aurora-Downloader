# Changelog

## 2.0.0 beta 2

- **Chromium support.** Works in Chrome, Edge, Brave (and should in Vivaldi/Opera) as well as Firefox. The extension is now Manifest V3, the installer registers the helper for every supported browser, and `install.bat` prints how to load it in each.
- **Fixed:** the update button offering "the same version" and then failing. yt-dlp and ffmpeg are only offered when really newer than the installed file; if winget refuses, the helper tries yt-dlp's own updater and shows what winget actually said.
- "Use my browser login" now takes cookies from the browser you pick (or the one you are using).
- Update checker understands beta numbers (beta 2 -> beta 3 -> final).
- The job list survives the browser sleeping the extension (Chromium); an update check also runs on a timer alarm.
