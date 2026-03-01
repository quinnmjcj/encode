#!/usr/bin/pwsh

param (
 [Parameter(Mandatory = $true, Position = 0)]
 [string]$input_name,
 [Parameter(Mandatory = $false)]
 [string]$encode="",
 [switch]$only=$false,
 [switch]$none=$false,
 [string]$group=""

)

Import-Module MediaUtils

$file = Get-ChildItem $input_name

$info = Get_Media_Info $file.FullName

$base = $file.BaseName
$height = Get_video_height $info
$oheight = Get_video_original_height $info
$width = Get_video_width $info
$hdr = Is_Display_BT2020 $info
$dv_type = Video_dv_type $info

#Write-Host $height $oheight $width $hdr $dv_type

if (($height -eq 2160) -or ($width -eq 3840)) {
    if ( !$hdr ) {
        if (($oheight -eq 1080) -and ($width -eq 1920)) {
            $type = "1080p"
        }
        elseif ($dv_type -eq "05.06") {
            $type = "4K_dv5"
        }
        else {
            $type = "4K SDR"
        }
    }
    else {
        $type = "4K"
        if ($dv_type -match "\d(\d)\.\d\d") {
            $type += "_dv" + $matches[1]
        }
    }
}
else {
    if (($height -eq 1080) -or ($width -eq 1920)) {
        $type  = "1080p"
    }
    elseif ($height -eq 720) {
        $type =" 720p"
    }
    elseif ($height -eq 480) {
        $type = "480p"
    }
    elseif ($height -eq 576) {
        $type = "576p"
    }
    else {
        $type = [string]$width + "x" + [string]$height
    }
    if ( $hdr ) {
        $type += " HDR"
    }
}

if ($base -match "(.+)\.([rqmv]\d+.*)") {
    $comp = $matches[2]
    $name = $matches[1]
}
elseif ($base -match "(.+)\.(bray.*)") {
    $comp = $matches[2]
    $name = $matches[1]
}
elseif ($base -match "(.+)\.(web)") {
    $comp = "web"
    $name = $matches[1]
}
else {
    $comp = ""
    if ($base -match "(.+) \(Bluray-1080p\)") {
        $name = $matches[1]
    }
    elseif ($base -match "(.+) \(Bluray-2160p( .*)?\)") {
        $name = $matches[1]
    }
    elseif ($base -match "(.+) \(WEBDL-\d\d\d\dp( .*)?\)") {
        $comp = "web"
        $name = $matches[1]
    }
    elseif ($base -match "(.+) \(WEBRip-\d\d\d\dp( .*)?\)") {
        $comp = "webrip"
        $name = $matches[1]
    }
     elseif ($base -match "(.+) \(SDTV\)") {
        $name = $matches[1]
    }
    else {
        $name = $base
    }
}

if ($encode -ne "") {
    $comp = $encode
}


$title = $name
if ((! $none)) {
    $title += " ("
    if (-not $only) {
        $title += $type
        if ($comp -ne "") {
            $title += ", "
        }
    }
    if ($comp -ne "") {
        $title += $comp
    }
    $title += ")"
}
#Write-Host $base " - " $title

$s = [string]$file.FullName
$t = Get_Title $info
$t2 = $title + " /"
if ($t.Length -gt $t2.Length) {
    $comp = $t.substring(0,$t2.Length)
}
else {
    $comp = $title
}
if (($group -ne "") -and ($group -ne "none")) {
    $title += " [$group]"
}
if (($t -ne $title)) {
    Write-Host("Set new title to '$title' (from '$t')")
    Change_title  $s $title
}
