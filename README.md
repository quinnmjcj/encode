This project creates a powershell encode script for encoding mkv videos to x264 or x265 (including Dolby Vision).
These scripts work in Linux and in Windows 10/11.

A little more documentation will be forthcoming, but you can look at encode.ps1 for the options for encoding.

You can do encodes like:
encode a.mkv -avc -crf 18 -noise nlmeans1
use nlmeans ONLY for 8-bit avc
encode a.mkv -crf 19 -noise vague0 -mel
encode a.mkv -crf 17 -tune animation 

These scripts are most likely useful as a starting point for encoding the way you want to encode.
