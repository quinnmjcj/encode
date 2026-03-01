This project creates a powershell encode script for encoding mkv videos to x264 or x265 (including Dolby Vision).
These scripts work in Linux and in Windows 10/11.

A little more documentation will be forthcoming, but you can look at encode.ps1 for the options for encoding.

You can do encodes like:
encode a.mkv -avc -crf 18 -noise nlmeans1     ### (use nlmeans ONLY for 8-bit avc)

encode a.mkv -crf 19 -noise vague0 -mel

encode a.mkv -crf 17 -tune animation 

These scripts are most likely useful as a starting point for encoding the way you want to encode.

To handle dolby vision encoding, you need to get  dovi_tool.  If you want to do "baking", you also need cm_analyze from dolby.

THis is the analysis using cursor AI (actually pretty impressive)

encode.ps1: Main HDR/Dolby Vision encode pipeline. It:
Parses many CLI options (input, cropping, CRF/preset/tune/noise, deinterlacing, Dolby Vision flags, HDR10+, MaxCLL/master-display overrides, etc.).
Uses custom modules (MediaOS, MediaUtils, SystemUtils) to get media info, build file names, log, and wrap tools.
Validates the input and determines:
Resolution/aspect, HDR10+/DV presence and type, colorspace, duration.
Output base name and a rich “extra info” suffix based on preset/CRF/tune/noise/interlacing/DV type.
Builds lots of derived file paths (BL/EL/RPU files, JSON configs, AVS scripts, temp ProRes, MaxCLL files, etc.).
Runs a sync test on the source MKV.
Extracts HEVC and Dolby Vision layers, analyzes and possibly bakes / converts DV and HDR10+ (via dovi_tool and custom helpers) and figures out borders/cropping from RPU.
Derives luminance and MaxCLL (from MediaInfo or through ProRes + cm_analyze), reconciles conflicting values, and optionally rewrites L6 DV metadata.
Builds an ffmpeg filter chain (noise, deinterlacing, scaling, cropping, test sampling, user filters).
Pipes ffmpeg (y4m) → x265 with a carefully constructed argument list (standard + various “modified” presets, psy tweaks, thread config).
Optionally injects RPU into the HEVC bitstream (via Dovi_inject / dovi_tool) and then calls mkv_remux.ps1 and video.ps1 retitle to produce the final MKV.

mkv_remux.ps1: Given an encoded video elementary stream + a “master” MKV, it:
Parses tracks from mkvinfo output with regexes.
Selects which audio/subtitle tracks to keep (respecting -lang, -all, ignore lists, defaults).
Builds a JSON “argument file” (.json) that is then passed to mkvmerge @file to:
Attach selected audio/subtitle tracks.
Copy chapters.
Set track languages, names, defaults, sync offsets.
Optionally set BT.709 colour flags and MaxCLL/FALL.
Renames the temp MKV to the final output.

RetitleMkv.ps1: Uses MediaUtils to:
Get resolution/original resolution, HDR flag, DV type, existing title.
Compute a type string (e.g. 4K, 4K_dv7, 1080p HDR, 720p, etc.).
Derive a compression tag from the filename or -encode (e.g. r19, v19, web, bray…).
Build a new title "<name> (<type, comp>) [group]" and call Change_title if different.
