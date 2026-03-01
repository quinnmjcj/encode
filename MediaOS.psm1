
$info = 2     # 1 means windows, 0 means linux

function Is_Windows {
    if ($info -ne 2) {
        if ($info -eq 0) { return $false }
        return $true
     }
     if (Test-Path  -Path "c:\_Bin" -PathType Container) {
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
     if (Test-Path  -Path "/home/mike/mux" -PathType Container) {
        $info = 2
        return $true
     }
     $info = 0
     return $false
}


function NasPrefix { If (Is_Windows) { return "\\qnas\" } else { return "/home/mike/qnas/" } }
function NasMovies {  $a = NasPrefix; return $a  + "movies" + $global:separator }
function NasTV {  $a = NasPrefix; return $a  + "tv" + $global:separator }
function NasData {  $a = NasPrefix; return $a  + "data" + $global:separator }
function NasAppdata { $a = NasPrefix; return $a  + "appdata" + $global:separator }

function Test_Mount {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$name
    )
    if (Is_Windows) {
        return $true
    }
    $a = & findmnt --mountpoint $name
    return $?
}


function StuffDir { if (Is_Windows) { return "V:\" } else { return "/home/mike/work/" } }
function ProresDir { if (Is_Windows) { return "V:\Prores\" } else { return "/home/mike/fasttemp/encode/" } }
function MuxDir { if (Is_Windows) { return "c:\mux\" } else { return "/home/mike/fasttemp/mux/" } }
function SepVal { if (Is_Windows) { return "\" } else { return "/" } }
function EncDir { if (Is_Windows) { return "q:\encode\" } else { return "/home/mike/fasttemp/encode/" } }
function TmpDir { if (Is_Windows) { return "q:\temp\" } else { return "/home/mike/fasttemp/temp/" } }
function MuxDir { if (Is_Windows) { return "q:\mux\" } else { return "/home/mike/fasttemp/mux/" } }
function MediaInfo { if (Is_Windows) { return "MediaInfo_cli" } else { return "/usr/bin/mediainfo" } }
function Hdr10Tool { if (Is_Windows) { return "C:\_Draginstall\hdr10plus\hdr10plus_tool.exe" } else { return "hdr10plus_tool" } }
function NullDev { if (Is_Windows) { return "nul" } else { return "/dev/null" } }
function LockFile { $a = StuffDir; $a += SepVal; return $a + "disk.lock" }

function TaskSet { if (Is_Windows) { return "" } else { return "taskset -c 2-29 nice -n 18 " } }

function Lang  { if (Is_Windows) { return "en" } else { return "en_US" } }
#
# NOTE: The only difference between the two verson of compiler was in documention - no code was touched between the two.
#
# x265 is 3.5+1-f0c1022b6 on linux
#
#function HevcComp { if (Is_Windows) { return "x265-4.0+23-487105d" } else { return "x265-4_0-6318f22" } }
function HevcComp { if (Is_Windows) { return "x265-4.0+23-487105d" } else { return "x265" } }
function x264Comp { if (Is_Windows) { return "x264-r3107-a8b68eb" } else { return "x264" } }

#function CmdVal { if (Is_Windows) { return "cmd /c " } else { return "bash " } }


$global:mkvinfo = "mkvinfo"
$global:mkvpropedit = "mkvpropedit"
$global:mkvmerge = "mkvmerge"
$global:ffmpeg = "ffmpeg"
$global:ffprobe = "ffprobe"
$global:dovi_tool = "dovi_tool"
$global:mkvextract = "mkvextract"
$global:ffmsindex = "ffmsindex"
$global:mediainfo = MediaInfo
$global:x265 = HevcComp
$global:x264 = x264Comp

$global:separator = SepVal


$global:enc_dir = EncDir
$global:tmp_dir = TmpDir
$global:mux_dir = MuxDir
$global:stuff_dir = StuffDir
$global:null_output = NullDev
$global:lock_dir = StuffDir
$global:lock_file = LockFile


$global:hdr10plus_tool = Hdr10Tool

$global:lang = Lang

if (Is_Windows) {
    if ( -not (Test-Path -Path "q:\" -PathType Container)) {
        & subst q: c:\fasttemp
    }
}
