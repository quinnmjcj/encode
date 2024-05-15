param (
 [Parameter(Mandatory = $true, Position = 0)]
 [string]$input_video,
 [Parameter(Mandatory = $true, Position = 1)]
 [string]$input_master,
 [Parameter(Mandatory = $true, Position = 2)]
 [string]$output_file,
 [string]$async,                   # audio sync offset
 [string]$ssync,                   # subtitle sync offset
 [string]$lang,                    # Specify language for main audio (for foreign films)
 [string]$aignore,                 # List of audio tracks to ignore
 [string]$signore,                 # List of subtitle tracks to ignore
 [switch]$chatty=$false,
 [switch]$bt709=$false,
 [switch]$all=$false,              # Copy all subtitles and audio tracks
 [int]$length=0
)

Import-module MediaUtils

if (! $aignore ) {
    $aignore_list = @()
}
else {
    $aignore_list = [int[]]($aignore -split ',')
}
if (! $signore ) {
    $signore_list = @()
}
else {
    $signore_list = [int[]]($signore -split ',')
}



$global:file = ""

$enc = [System.Text.Encoding]::UTF8

$length = 0

$output_file_tmp = $output_file + ".tmp.mkv"

function FixName
{

    Param ([string]$s)
    return $s.Replace('"', '\"')
}

function MergeStart
{
    "[" | Out-File -encoding utf8  $global:file
}


function MergeOut
{
    Param ([string]$value)
    Add-Content $global:file "  `"$value`","
}

function FileNameOut
{
    Param ([string]$value)
    $temp = $value.Replace("\", "\\")
    Add-Content $global:file "  `"$temp`","

}

function MergeOutLast
{
    Param ([string]$value)
    Add-Content $global:file "  `"$value`""
}

function MergeOutLiteral
{
    Param ([string]$value)
    Add-Content $global:file "$value"
}

function AudioOut
{
    Param ([string]$tno, [string]$lang, [string]$name, [int]$def)

    MergeOut "--language"
    MergeOut ($tno + ":" + $lang)
    MergeOut "--track-name"
    $name = FixName($name)
    #$temp=[System.Text.Encoding]::UTF8.GetBytes($name)
    MergeOut ($tno + ":" + $name)
    if ($def -eq 1) {
        MergeOut "--default-track"
        MergeOut ($tno + ":yes")
    }
    else {
        MergeOut "--default-track"
        MergeOut ($tno + ":no")
   }
}

function SubOut
{
    Param ([string]$tno, [string]$lang, [string]$name, [int]$def)

    if ($lang -eq "") {
        $lang = "eng"
    }
    if ($name -eq "English") {
        $name = ""
    }
    elseif ($name -eq "English (SDH)") {
        $name = "SDH"
    }

    Write-Host("Track $tno : $lang ($name)")
    MergeOut "--language"
    MergeOut ($tno + ":" + $lang)
    if ($name -and $name -ne "") {
        MergeOut "--track-name"
        $name = FixName($name)
        MergeOut ($tno + ":" + $name)  
    }
    MergeOut "--default-track"
    $tmp = if ($def) { "yes" } else { "no" }
    MergeOut ($tno + ":" + $tmp)
}


$infull = resolve-path $input_master
$infile = $infull.Path

$info = & $global:mkvinfo $infile
$video_info = Get_Media_Info($infile)


$subidx = 0   
$audidx = 0               # 0 is the main channel audio
$state = 0
$width = Get_Video_Width $video_info
$height = Get_Video_Height $video_info
$vidtype = ""

$yuv420p10le = $false
#
# Some disks have a LOT of subtitles!
#
$subtitles = @(0)
$subname = @("")
$sublang = @("")
$subdef = @(0)

while ($subdef.Count -lt 60) {
    $subtitles += @(0)
    $subname += @("")
    $sublang += @("")
    $subdef += @(0)
}



[int[]]$audio = @(0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0)
$audtype = @("","","","","","","","","","", "","","","","","","","","","", "","","","","","","","","","")
[int[]]$audchannels = @(0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0)
$audname = @("","","","","","","","","","", "","","","","","","","","","", "","","","","","","","","","")
$audlang = @("","","","","","","","","","", "","","","","","","","","","", "","","","","","","","","","")

$a =  @('\| \+ Track', 
        '\|  \+ Track number: \d+ \(track ID for mkvmerge & mkvextract: (\d+)\)',
        '\|  \+ Track type: ([a-z]+)',    # 2
        '\|  \+ Language: ([a-z]+)',      #3
        '\|  \+ Default flag: ([01])',    #4
        '\|  \+ Codec ID: ([_a-zA-Z]+)',  #5
        '\|  \+ Language: ([a-z]+)',      #6
        '\|  \+ Name: (.*)',              #7
        '\|   \+ Channels: (\d+)'         #8
        '\|  \+ Default duration: [\d\:\.]+ \(([\.\d]+) frames/field.*',
        '\| \+ EbmlVoid', 
        '\|   \+ Pixel width: (\d+)',     #11
        '\|   \+ Pixel height: (\d+)',    #12
        '\|\+ Segment tracks',       #13
        '\| \+ Duration: (\d\d):(\d\d):(\d\d).(\d\d\d)\d\d\d\d\d\d',           #14
        '\|  \+ Codec.* \(HEVC profile: Main 10 .*\)',   #15
        '\|\+ Segment information'       #16

 
     )

$state = 1
$saw_video = $false

foreach ($line in $info)
{
    # Test for "A track"
    if ( $line -match $a[0] ) {
        $state = 10
        continue
    }
    # Test for "Segment information"
    if ( $line -match $a[16] ) {
        $state = 0
        continue
    }
    if ( $line -match $a[10] ) {
        $state = 1
    }
    switch ($state) {
        # Segment informaiton
        0
        {
            if ($line -match $a[14] ) {
                $hr = [int]$matches[1]
                $min = [int]$matches[2]
                $sec = [int]$matches[3]
                $ms = [int]$matches[4]
                $duration = ((($hr * 60) + $min)*60 + $sec) * 1000 + $ms
                #Write-Output("Duration = $duration")
            }
        }
        # Ignore
        1
        {
        }
        # A Track
        10
        {
            if ( $line -match $a[1] ) {
                $track = $matches[1]
            }    
            elseif ( $line -match $a[2] ) {
                $tracktype = $matches[1]
                if ($chatty) {
                    Write-Host "Track $track is $tracktype"
                }
                switch ($tracktype) {
                    "subtitles"
                    {
                       if ($signore -and $signore_list -contains $track) {
                           $state = 1
                           continue
                       }
                       $subtitles[$subidx] = $track
                       $useidx = $subidx
                       $subidx += 1
                       $state = 20
                    }
                    "audio"
                    {
                        if ($aignore -and $aignore_list -contains $track) {
                            $state = 1
                            continue
                        }
                        $audio[$audidx] = $track
                        $useidx = $audidx
                        $audidx += 1
                        $state = 30
                    }
                    "video"
                    {
                        if ( $saw_video ) {
                            Write-Error "Video has 2 video tracks - exitting"
                            exit 1
                        }
                        $saw_video = $true
                        $state = 40
                    }
                }
            }               
        }
        # Subtitle Track
        20
        {
           if ( $line -match $a[3] ) {               # Language
               if ( (-not $all) -and ($matches[1] -ne "eng") ) {
                    $subidx -= 1
                    $state = 1
                    continue
                }
                $sublang[$useidx] = $matches[1]
            }
            elseif ( $line -match $a[7] ) {              # Name
                $subname[$useidx] = $matches[1]
            }
            elseif ( $line -match $a[4] ) {
                $subdef[$useidx] =  if ($matches[1] -eq "1") { 1 } else { 0 }
            }    
        }
        # Audio Track
        30
        {
            if ( $line -match $a[5] ) {                     # Audio type
                $audtype[$useidx] = $matches[1]
            }
            elseif ( $line -match $a[6] ) {                     # Audio language
                if ( (-not $all) -and ($matches[1] -ne "eng") -and ($matches[1] -ne $lang) ) {
                    $audidx -= 1
                    $state = 1;
                    continue;
                }
                $audlang[$useidx] = $matches[1]
            }
            elseif ( $line -match $a[7] ) {                      # Audio name
                $audname[$useidx] = $matches[1]
            }
            elseif ( $line -match $a[8] ) {                      # Audio Channels...
                $audchannels[$useidx] = $matches[1]
 
            }
        }        
        # Video Track
        40
        {
             if ( $line -match $a[9] ) {
                 if (!$speed) {
                    $x = $matches[1]
                    if ($x -eq "24.000") {
                        $x = "24"
                    }
                     if ($x -eq "25.000") {
                        $x = "25"
                    }
                   $speed = $x
                }
            }
            if ( $line -match $a[5] ) {
                $vidtype = $matches[1]
            }
            if ( $line -match $a[11] ) {
                $width = [int]$matches[1]
                if ($chatty) {
                    Write-Host "width = $width"
                }
            }
            if ( $line -match $a[12] ) {
               $height = [int]$matches[1]
               if ($chatty) {
                   Write-Host "height = $height"
               }
            }
            if ( $line -match $a[15] ) {
                $yuv420p10le = $true
            }      
        }
    }
}


#
# Here, the video and audio tracks exist - it's time to remux the video
#

$global:file = $output_file + ".json"

$output_tmp = $output_file + ".tmp.mkv"

$todel_list += @($global:file)

MergeStart
MergeOut "--ui-language"
MergeOut $global:lang
MergeOut "--output"
FileNameOut "$output_file_tmp"

MergeOut "--no-video"

#
# NOTE: We'll inherit the chapters directly, since we didn't specify --no-chapters
#

$order=""

for ($j = 0; $j -lt $audio.length; $j++)
{
    if (($audio[$j] -ne 0) ) {
        if ($atracks) {
            $atracks += "," 
        }
        $atracks += [string]$audio[$j]
    }
}

for ($j = 0; $j -lt $subtitles.length; $j++)
{
    if (($subtitles[$j] -ne 0)) {
        if ($stracks) {
            $stracks += "," 
        }
        $stracks += [string]$subtitles[$j]
    }
}

MergeOut "--audio-tracks"
MergeOut $atracks
if ($stracks) {
    MergeOut "--subtitle-tracks"
    MergeOut $stracks
}
else {
    MergeOut "--no-subtitles"
}

for ($j = 0; $j -lt $audio.length; $j++)
{

    if ($audio[$j] -ne 0) {
        $uselang = $audlang[$j]
        if ($uselang -eq "") {
            $uselang = "eng"
        }
        $usename = $audname[$j]
        AudioOut $audio[$j] $uselang $usename $i 0
        $order += ",0:" + $audio[$j]
        if ($async) {
            MergeOut "--sync"
            MergeOut ([string]$audio[$j] + ":" + $async)
        } 

    }
}

for ($j = 0; $j -lt $subidx; $j++)
{
    $name = $subname[$j]
    SubOut $subtitles[$j] $sublang[$j] $name $subdef[$j]
    if ($ssync) {
        MergeOut "--sync"
        MergeOut ([string]$subtitles[$j] + ":" + $ssync)
    } 
    $order += ",0:" + $subtitles[$j]
}

#
# File #0 = audio file.
# This needs to be modified if we reencode audio
#
MergeOut "("
FileNameOut $infile
MergeOut ")"


MergeOut "--language"
MergeOut ("0:eng")
#
# For BT.709 HD to properly be flagged as BT.709
#
if ($bt709) {
    MergeOut "--colour-matrix-coefficients"
    MergeOut "0:1"
    MergeOut "--colour-range"
    MergeOut "0:1"
    MergeOut "--colour-transfer-characteristics"
    MergeOut "0:1"
    MergeOut "--colour-primaries"
    MergeOut "0:1"
}
MergeOut "("
FileNameOut $input_video
MergeOut ")"
if ($length -ne 0) {
    MergeOut "--split"
    $temp = "parts:0s-" + $length.ToString() + "s"
    MergeOut $temp
}
MergeOut "--track-order"
MergeOutLast ("1:0" + $order)
MergeOutLiteral "]"

$arg = "`"@" + $global:file + "`""
$arg = "@" + $global:file 

Write-Output $global:mkvmerge $arg
& $global:mkvmerge $arg
if ($LASTEXITCODE -ne 0) {
  Exit(1)
}
Write-Host "Rename $output_file_tmp to $output_file"
Rename-Item $output_file_tmp $output_file
Remove-item $global:file
