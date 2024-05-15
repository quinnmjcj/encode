param (
 [Parameter(Mandatory = $true, Position = 0)]
 [string]$input_name,
 [Parameter(Mandatory = $false)]
 [string]$encode="",
 [switch]$only=$false,
 [switch]$none=$false
)

Import-Module MediaUtils

$file = gci $input_name

$info = Get_Media_Info $file.FullName

$base = $file.BaseName
$height = Get_video_height $info
$width = Get_video_width $info
$hdr = Is_Display_BT2020 $info

if (($height -eq 2160) -or ($width -eq 3840)) {
    if ( !$hdr ) {
        $type = "4K SDR"
    }
    else {
        $type = "4K"
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
    $name = $base
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
if (($t -ne $title)) {
    Write-Host("Set new title to '$title' (from '$t')")
    Change_title  $s $title
}


