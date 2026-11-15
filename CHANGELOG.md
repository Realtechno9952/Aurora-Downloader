# Changelog

## 2.0.0 beta 4

- **New name: Aurora Downloader.** The extension, installer and uninstaller use the new name. Nothing about how it works changed, and existing installs keep working.
- **Login works in Chrome, Edge, Brave and Helium.** Those browsers lock their cookies away from yt-dlp, so the extension now reads the site's cookies itself and gives them to the helper in a temporary file that is deleted when the download ends. It only does this after you allow the browser's cookie permission (the popup asks when you switch the login on). Firefox is unchanged.
- **Deno warning.** On a YouTube page, the popup tells you if Deno is missing and has an Install Deno button.
- Pages yt-dlp has no special support for now send the page address as the Referer, which fixes some sites that check it.
- "Take login from" has a new Automatic option (the best choice for the browser you are using).

## 2.0.0 beta 3

- **Open file** button when a download finishes, and on each history entry.
- **Fixed:** Chromium refused to load the extension (`background.scripts` is not allowed there). Firefox and Chromium now have their own manifest; Chromium browsers load the `extension-chromium` folder that `install.bat` makes.
- **Fixed:** the "Take login from" dropdown was white on white in Chromium browsers.
- Firefox no longer shows manifest warnings.
- Folders tidied: the tests now live in `tools/`.

## 2.0.0 beta 2

- **Chromium support.** Works in Chrome, Edge, Brave (and should in Vivaldi/Opera) as well as Firefox. The extension is now Manifest V3 and the installer registers the helper for every supported browser.
- **Fixed:** the update button offering "the same version" and then failing. yt-dlp and ffmpeg are only offered when really newer than the installed file; if winget refuses, the helper tries yt-dlp's own updater and shows what winget actually said.
- "Use my browser login" now takes cookies from the browser you pick (or the one you are using).
- Update checker understands beta numbers (beta 2 -> beta 3 -> final).
- The job list survives the browser sleeping the extension (Chromium); an update check also runs on a timer alarm.
