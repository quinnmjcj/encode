
$info = 2     # 1 means windows, 0 means linux

function Is_Windows {
    if ($info -ne 2) {
        if ($info -eq 0) { return $false }
        return $true
     }
     if (-not (Test-Path  -Path "/home/mike/mux" -PathType Container)) {
        $info = 1
        return $true
    }
    $info = 0
    return $false
}

function Is_Linux {
    if ($info -ne 2) {
        if ($info -eq 0) { return $true }
        return $false
     }
     if (-not (Test-Path  -Path "/home/mike/mux" -PathType Container)) {
        $info = 1
        return $false
     }
     $info = 0
     return $true
}

function SepVal { if (Is_Windows) { return "\" } else { return "/" } }
function EncDir { if (Is_Windows) { return "q:\encode\" } else { return "/home/mike/QDrive/encode/" } }
function TmpDir { if (Is_Windows) { return "q:\temp\" } else { return "/home/mike/QDrive/temp/" } }
function MuxDir { if (Is_Windows) { return "c:\mux\" } else { return "/home/mike/mux/" } }
function MediaInfo { if (Is_Windows) { return "MediaInfo_cli" } else { return "mediainfo" } }
function Hdr10Tool { if (Is_Windows) { return "C:\_Draginstall\hdr10plus\hdr10plus_tool.exe" } else { return "hdr10plus_tool" } }
function Lang  { if (Is_Windows) { return "en" } else { return "en_US" } }
#
# NOTE: The only difference between the two verson of compiler was in documention - no code was touched between the two.
#
function HevcComp { if (Is_Windows) { return "x265-3.6+7-53afbf5_vs2015" } else { return "x265-3.6+10-05d6a17db_gcc" } }
function x264Comp { if (Is_Windows) { return "x264-r3107-a8b68eb" } else { return "x264" } }

#function CmdVal { if (Is_Windows) { return "cmd /c " } else { return "bash " } }


$global:mkvinfo = "mkvinfo"
$global:mkvpropedit = "mkvpropedit"
$global:mkvmerge = "mkvmerge"
$global:ffmpeg = "ffmpeg"
$global:ffprobe = "ffprobe"
$global:dovi_tool = "dovi_tool"
$global:mkvextract = "mkvextract"
$global:mediainfo = "MediaInfo_cli"
$global:x265 = HevcComp       
$global:x264 = x264Comp

$global:separator = SepVal


$global:enc_dir = EncDir
$global:tmp_dir = TmpDir
$global:mux_dir = MuxDir



$global:hdr10plus_tool = Hdr10Tool

$global:lang = Lang

