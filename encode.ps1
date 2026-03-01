#!/usr/bin/pwsh
#
# Encode.ps1 - new version
#
param (
 [Parameter(Mandatory = $true, Position = 0)]
 [string]$Input_name,                   #N ame of input file
 [Parameter(Mandatory = $false)]
 [string]$Output = "",                  # Output file base name, if specified
 #
 # Cropping parameters
 #
 [int]$top=0,                           # Crop top
 [int]$bottom=0,                        # Crop bottom
 [int]$left=0,                          # Crop left
 [int]$right = 0,                       # Crop right
 [switch]$no_crop=$false,               # $true if we don't want to crop
 #
 [int]$qscale=8,                        # qscale to use if we prores encode
 #
 [int]$Crf=0,                           # CRF Value
 [ValidateSet('veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'default')]
   [string]$Preset="default",           # What compiler preset to use
 [ValidateSet('none', 'animation', 'grain')]
   [string]$Tune="none",                # -tune parameter for x264 or x265
 [string]$Noise="none",                 # Type of denoising desired
 [string]$Filters = "",                 # Extra filters for ffmpeg (e.g. scale-320:240,setsar=1:1)
 [int]$Inter=0,                         # Set inter processing
 [switch]$No_bt709=$false,              # Don't set bt709 if it's not BT2020
  [switch]$Tff=$false,
 [switch]$Bff=$false,
 [switch]$Yadif=$false,
 [switch]$Nnedi3=$false,
 [int]$Kerndeint=-1,
 #
 [switch]$Amp=$false,                 # $true if we want to use --amp in hevc slower
 [switch]$No_slower_mods = $false,    # Turn of special handling for slower hevc preset
 [switch]$No_specials = $false,       # Turn of all special handling
 #
 # Switches we don't use often
 #
 [string]$Threads="std",                # std means our reduced number of threads, default means x265 default. none is none
 [string]$Maxcll="",                    # Override maxcll value
 [string]$Master_display="",            # Override Master Display value
 [switch]$Mel=$false,                   # Don't do FEL baking....
 [switch]$Extra,                        # Set if we're encoding an "extra"
 [switch]$Dv_type,                      # Calculate the dv_type
 [switch]$No_dv,                        # Don't process Dolby Vision
 [switch]$Hdr10plus2dv,                 # convert hdr10+ to Dolby Vision, even if it already exists
 [switch]$Keep_dv,                      # Keep DV 8.0.6 rather than to hdr10+ conversion
 [switch]$No_hdr10plus,                 # Don't keep hdr10+
 [switch]$No_touchl6=$false,            # Don't modify the level 6 DV information
 [switch]$no_touch_borders,             # Don't mess with border calcs - usually because it's variable aspect ratio
 [switch]$Force_encode = $false,        # Ignore an existing tmp encode file
 [string]$Group="none",                 # Release Group
 [switch]$Calc_maxcll=$false,
 [int]$trim = 0,                        # for when BL and EL don't have the same number of frames.

 [switch]$Notest = $false,              # Don't do a sync test
 [switch]$nocrop = $false,              # Don't do crop to RPU'
 [switch]$Prep = $false,
 [switch]$No_split = $false
)

Import-Module MediaOS, MediaUtils, SystemUtils

function StringIze {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $array
    )
    return [string]($array[0]) + "," + [string]($array[1])
}

$level = "m"
#
# Set up variables to put everything together
#
$args_spcl = @()
$args_filter = @()
$args_ffmpeg_ext =  @()

if ($dvtype) { $notest = $true }

#
# Insure the input file exists
#
if (-not (Test-Path -Path $Input_name -PathType Leaf) ) {
    FatalError "File '$Input_name' does not exist!"
}
$input_file = Get-ChildItem $Input_name

$g = Get_Group $input_file

if (($group -ne $g) -and ("none" -ne $g) -and ("none" -ne $group)) {
    Warning "Group mismatch - file name specifies $g"
}
else {
    $group = $g
}
Info "Using group $group"

#
# Create our output base name
#
if ($Output -eq "") {
    $output_base_name = Strip_file_name $Input_name
}
else {
    $output_base_name = $Output
}

$video_info = Get_Media_info $Input_name
$height = Get_Video_Height $video_info
$width = Get_Video_Width $video_info
$hdr10plus = Video_has_hdr10 $video_info
$dv_info = Video_dv_type $video_info
$duration = Get_video_duration $video_info
$colorspace = Search_video_info $video_info "Color primaries"

if (($height -eq 0) -or ($width -eq 0)) {
    FatalError "Can't determine video size"
}
#
# Turn off $hdr10plus processing, if requested
#
if ($No_hdr10plus) {
    $hdr10plus = $false
}
#
# Turn of DV processing if $No_dv is set
#

if ($No_dv -and ($dv_type -eq $false)) {
   $dv_info = ""
}

$dv = 0
if (("" -ne $dv_info) -and ("08.06" -ne $dv_info) -and ("07.06" -ne $dv_info) -and ("07.09" -ne $dv_info)) {
    FatalError "Cannot convert dv type $dv_info"
}
if ("" -ne $dv_info) {
    $dv = ([int]($dv_info[1])) - 48
    if (($dv -ne 7) -and ($dv -ne 8)) { ERROR "Bad Dolby type $dv" }
}

if ($dv_type) {
    if ("" -eq $dv_info) {
        FatalError "No Dolby Vision on this file"
    }
    if (8 -eq $dv) {
        FatalError "Dolby Type is 8.06 (RPU only)"
    }
}


$a = "none"

$files_hash = Create_file_names $video_info $output_base_name $a $a

#
# None of these names depends on the encode parameters for the file
#
$sync_ok_file = $files_hash["sync_ok_file"]
$hdr10_json = $files_hash["hdr10_json"]
$extr_file = $files_hash["extr_file"]
$bl_file = $files_hash["bl_file"]
$el_file = $files_hash["el_rpu_file"]
$rpu_file = $files_hash["rpu_file"]
$chp_file = $files_hash["chapter_file"]
$borders_file = $files_hash["borders_file"]

$bl_index = $bl_file + ".ffindex"
$el_index = $el_file + ".ffindex"
$bl_tmpindex = $bl_file + ".tmp.index"
$el_tmpindex = $el_file + ".tmp.index"
$avs_file = $files_hash["base_name"] + ".avs"
$avs_prores_file = $files_hash["base_name"] + ".prores.avs"
$rpufel_file = $files_hash["base_name"] + ".fel.rpu.bin"
$rpup8_file = $files_hash["base_name"] + ".p8.rpu.bin"
$rpul6_file = $files_hash["base_name"] + ".p8l6.rpu.bin"
$rpu_file = $files_hash["base_name"] + ".rpu.bin"
$xml_base = $files_hash["base_name"] + ".analysis.$qscale."

$p8_json =$files_hash["base_name"] + ".p8.json"
$l6_json = $files_hash["base_name"] + ".l6.json"
$crop_json = $files_hash["base_name"] + ".crop.json"
$rpu_info_file = $files_hash["base_name"] + ".rpuinfo.txt"
$maxcll_file = $files_hash["base_name"] + ".maxcll.txt"

$mov_file = $files_hash["base_name"] + "." + [string]$qscale + ".prores.mov"
$mov_pieces = $files_hash["base_name"]  + "." + [string]$qscale + ".prores.*.mov"
$mov_template = $files_hash["base_name"]  + "." + [string]$qscale + ".prores.%d.mov"
$movtmp_file = $files_hash["base_name"] + "." + [string]$qscale + ".tmp.mov"

#
######################################################################################
# Create our "extra info"
#####################################################################################
#
#
# Calculate default CRF, if necessary
#
if ($crf -eq 0) {
    if ( $extra ) {
        $crf = if ( -not $Avc ) { 25 } else { 22 }
    }
    else {
        $crf = 19
    }
}
#
# Set default preset
#
if ($Preset -eq "default") {
    if ($avc) {
        $Preset = "veryslow"
    }
    else {
        $Preset = "slower"
    }
}

#
# Setup the extra information on the file name
# format = [preset][crf][tune][filter][encode-type]_[dolby-type]
#
if ($Preset -eq "medium") {
    $extra_info = "m"
}
elseif ($preset -eq "slower") {
    $extra_info = "r"
}
elseif ($preset -eq "veryslow") {
    if ($Avc) {
        $extra_info = "q"
    }
    else {
        $extra_info = "v"
    }
}
elseif ($preset -eq "slow") {
    $extra_info = "s"
}
else {
    $extra_info = "x"
}
$extra_info += [string]$crf
#
# Add extra tune information
#
if ($Tune -eq "animation") {
    $extra_info += "A"
}
elseif ($Tune -eq "grain") {
    $extra_info += "g"
}
#
#
# Add denoising information
#

$filter = ""
$intex = ""

if ($Noise -match "vague(\d)([\+\-]?)") {
    $tmp = ""
    $x = $matches[2]
    $y = $matches[1]
    switch ($y) {
        "0" { $tmp = "1:0:6:85:15" }
        "1" { $tmp = "2:2:6:50:15" }
        "2" { $tmp = "2:2:6:85:15" }
        "3" { $tmp = "3:2:6:85:15" }
    }
    $z = 1000
    switch ($x) {
        ""   {  $z = 25 }
        "+"  {  $z = 100 }
        "-"  {  $z = 0 }
    }
    #
    # AVC encoding does use the inter stuff
    #
    if ($avc) {
        $x = ""
    }
    if (($z -eq 1000) -or ( $tmp -eq "")) {
        FatalError "Unknown -noise value = $Noise"
    }
    if ($Inter -ne 0) {
            $intex = "E" + [string]$Inter
    }
    else {
        $Inter = $z
    }

    $extra_info += "v" + $y + $x
    $filter = "vaguedenoiser=" + $tmp

}
elseif ("none" -ne $Noise) {
    FatalError "Unknown -noise value = $Noise"

}
#
# Deal with the exceptions to our "modifications"
#
if ($no_specials) {
    $extra_info += "z"
}
elseif ($Preset -eq "slower") {
    if ($no_slower_mods) {
        $extra_info += "n"
    }
    elseif ($amp) {
        $extra_info += "a"
    }

}

$extra_info += $intex

$extra_info +=  $level

$files_hash = Create_file_names $video_info $output_base_name $extra_info $extra_info

$output_enc_file = $files_hash["enc_file"]
#
# Handle some of the extra filter stuff
#
if ( $Extra ) {
    if ($filter -ne "") {
        $filter += ","
    }
    if ([int]$height -ge 720 -and [int]$width -ge 1280) {
        $filter += "scale=1280:720,yadif"
        $args_ffmpeg_extra += @("-sws_flags", "lanczos")
    }
    else {
        $filter += "yadif"
    }
}

if ($yadif) {
    if ($filter -ne "") { $filter += "," }
    $filter += "yadif"
}
if ($kerndeint -ge 0) {
    if ($filter -ne "") { $filter += "," }
    if ($kerndeint -eq 0) {
        $kerndeint = 10
    }
    if ($tff) {
        $filter += "kerndeint=order=1:thresh=" + [string]$kerndeint
        $tff = $false
    }
    elseif ($bff) {
        $filter += "kerndeint=order=0:thresh=" + [string]$kerndeint
        $bff = $false
    }
    else {
        $filter += "kerndeint=thresh=" + [string]$kerndeint
    }
}
if ($nnedi3) {
    if ($filter -ne "") { $filter += "," }
    $filter += "nnedi=weights=nnedi3_weights.bin"
}
if ($test_crf) {
    if ($filter -ne "") { $filter += "," }
    $filter += "select=lt(mod(n\,2400)\,120)"
}


if ($filters -ne "") {
    if ($filter -ne "") { $filter += "," }
    $filter += $filters
}


#
# Test the file Synchornization
#
if ((-not $notest) -and (-not (Test-Path -Path $sync_ok_file -PathType Leaf))) {
    Info "Testing Sync of mkv file"
    if (-not (Test_Mkv $input_file.FullName)) {
        FatalError "Sync errors in mkv file"
    }
    "ok" | Out-file $sync_ok_file
}

#
# Extract the internal information - this will extract an h264 or hevc, depending....
#

Extract_hevc 0 $input_file.FullName $extr_file

$old_ex = $extra_info

#
# If it has DV, extract the BL and el_rpu files, as well as the rpu.bin
#

$use_maxcll = @(0,0)

if (0 -ne $dv) {

    $hybrid = Is_Hybrid $input_file

    Extract_all_dovi_layers $extr_file $bl_file $el_file $rpu_file $rpufel_file

    $dv_list = Parse_dv_info $video_info $rpufel_file $el_file $mel $dv $hybrid

    $dolby = $dv_list[0]                        # 'M' or 'F'

    $extra_info = $old_ex + $dv_list[1]         # the extra extension (i.e. _dvmb)

    $mux_rpu = $true
    if ($dv_type) {
        FatalError $dv_list[2]                  # Show the DV_type
    }

    Info $dv_list[2]                            # Show the DV_type

    $dv = $dv_list[3]                           # Set the new DV_Type (it stays at 7 if we're baking)
}



$do_l6 = $false
#
# Handle Luminance and Maxcll from mediainfo
#
$ov_lum = $false
if ("" -ne $master_display) {
    $ov_lum = $true
    if ($master_display -match "(\d+),(\d+)") {
        $use_mdl = @([int]($matches[1]), [int]($matches[2]))
    }
    else {
        FatalError "Can't parse master_display parameter ($master_display)"
    }
}
else {
    $use_mdl = Get_mediainfo_luminance $video_info
    Info ("MediaInfo luminance  = " + (Stringize $use_mdl))
}
$ov_maxcll = $false
if ("" -ne $maxcll) {
    $ov_maxcll = $true
    if ($maxcll -match "(\d+),(\d+)") {
        $use_maxcll = @([int]($matches[1]), [int]($matches[2]))
    }
    else {
        FatalError "Can't parse maxcll parameter ($maxcll)"
    }
}
else {
    $use_maxcll = Get_mediainfo_maxcll $video_info
    Info ("MediaInfo maxcll  = " + (Stringize $use_maxcll))
}


#
# If there's HDR10+, create the json file,  and if no DV 7, create a Faux RPU file
#
if ($keep_dv -and $hdr10plus -and (8 -eq $dv)) {
    $hdr10plus = $false
}
if ($hdr10plus) {

    Info "Video has HDR10+ Profile"

    if (-not (Test-Path $hdr10_json -PathType Leaf)) {
        Info "Create Hdr10+ json file"
        Create_hdr10plus_json_file $extr_file $hdr10_json
    }

    $args_spcl += @("--dhdr10-info", """$hdr10_json""", "--dhdr10-opt")

    if ((7 -ne $dv) -or $hdr10plus2dv) {
        Info "Setting Dolby to _dv8p"
        $extra_info = $old_ex + "_dv8p"
        Remove-File $rpup8_file
        Create_dovi_layer_from_hdr10 $hdr10_json $rpup8_file $use_mdl $use_maxcll
        $mel = $false
        $mux_rpu = $true
        $dv = 9
    }

}
#
# Setup the final hash file name for output files
#
$files_hash = Create_file_names $video_info $output_base_name $old_ex $extra_info

$output_mkv = $files_hash["out_file"]

$dv_muxed_file = $files_hash["dv_file"]

$file_to_encode = $extr_file

#
# Setup luminance and maxcll from the video info
#


if (0 -ne $dv) {
    #
    # For type 9, we just create the rpu - any rpufel that exists is from somebody else, probably a hybrid
    # It used MediaInfo CLL, OR, we're going to create a new CLL
    #
    if (9 -ne $dv) {
        $rpu_maxcll = Get_L6_maxcll $rpufel_file
        $rpu_luminance = Get_l6_luminance $rpufel_file
        $l1_maxcll = Get_L1_maxcll $rpufel_file
        $l1_luminance = Get_l1_luminance $rpufel_file
        Info ("L1 maxcll  = " + (Stringize $l1_maxcll) + " L6 maxcll = " + (Stringize $rpu_maxcll))
        Info ("L1 luminance  = " + (Stringize $l1_luminance) + " L6 luminance = " + (Stringize $rpu_luminance))
        if ($false -eq $ov_maxcll) {
            if (($l1_maxcll[0] -ne $rpu_maxcll[0]) -or ($l1_maxcll[1] -ne $rpu_maxcll[1])) {
                Warning "Mismatch between L1 and L6 Maxcll"
            }
            if (($use_maxcll[0] -ne $rpu_maxcll[0]) -or ($use_maxcll[1] -ne $rpu_maxcll[1])) {
                Warning "Mismatch between MediaInfo and L6 Maxcll"
            }
            if (($use_maxcll[0] -ne $l1_maxcll[0]) -or ($use_maxcll[1] -ne $l1_maxcll[1])) {
                Warning "Mismatch between MediaInfo and L1 Maxcll"
            }
            $show_maxcll = "MediaInfo"
            if ($l1_maxcll[0] -gt $use_maxcll[0]) {
                $use_maxcll = $l1_maxcll
                $show_maxcll = "L1"
            }
            if ($rpu_maxcll[0] -gt $use_maxcll[0]) {
                $use_maxcll = $rpu_maxcll
                $show_maxcll = "L6"
            }
        }
        Info ("Using $show_maxcll maxcll = " + (StringIze $use_maxcll))
        if ($false -eq $ov_lum) {
            if (($l1_luminance[0] -ne $rpu_luminance[0]) -or ($l1_luminance[1] -ne $rpu_luminance[1])) {
                Warning "Mismatch between L1 and L6 Luminance"
            }
            if (($use_mdl[0] -ne $rpu_luminance[0]) -or ($use_mdl[1] -ne $rpu_luminance[1])) {
                Warning "Mismatch between MediaInfo and L6 Maxcll"
            }
            if (($use_mdl[0] -ne $l1_luminance[0]) -or ($use_mdl[1] -ne $l1_luminance[1])) {
                Warning "Mismatch between MediaInfo and L1 Maxcll"
            }
            $show_mdl = "MediaInfo"
            if ($l1_luminance[0] -gt $use_mdl[0]) {
                $use_mdl = $l1_luminance
                $show_mdl = "L1"
            }
            if ($rpu_luminance[0] -gt $use_mdl[0]) {
                $use_mdl = $rpu_luminance
                $show_mdl = "L6"
            }
        }
    }

    if (9 -eq $dv) {
        $t = (&$global:dovi_tool info -s $rpup8_file)
    }
    else {
        $t = (&$global:dovi_tool info -s $rpufel_file)
    }

    $tt = ($t | Select-string -pattern "Frames\: (\d+)")
    $tt = [string]$tt
    if ($tt -match "Frames\: (\d+)") { $nframes = $matches[1]} else { FatalError "Can't parse RPU" }
    Info "Number of Frames = $nframes"
    if ((0 -ne $top) -or (0 -ne $left) -or (0 -ne $bottom) -or (0 -ne $right)) {
        $t = $top; $b = $bottom; $l = $left; $r = $right
        Warning "Overridden borders are ($t, $l, $b, $r)"
    }
    elseif (Test-Path $borders_file -PathType Leaf) {
        $tt = Get-Content -Path $borders_file
        if ($tt -match "-top (\d+) -bottom (\d+) -left (\d+) -right (\d+)") {
            $t = $matches[1]
            $b = $matches[2]
            $l = $matches[3]
            $r = $matches[4]
        }
        else {
            FatalError "Can't parse border file ($borders_file)"
        }

        Info "Borders are ($t, $l, $b, $r)"
        "-top $t -bottom $b -left $l -right $r" | Out-file $borders_file
    }
    elseif (9 -ne $dv) {
        if (-not $nocrop) {
            Info "Checking borders"
            $a = ( &$global:dovi_tool info -i $rpufel_file -f 60)
            $ts = ($a | Select-string -pattern ".*active_area_top_offset""`: (\d+).*")
            $bs = ($a | Select-string -pattern ".*active_area_bottom_offset""`: (\d+).*")
            $ls = ($a | Select-string -pattern ".*active_area_left_offset""`: (\d+).*")
            $rs = ($a | Select-string -pattern ".*active_area_right_offset""`: (\d+).*")
            $t = -1
            $b = -1
            $l = -1
            $r = -1
            if (($ts -eq $null) -and ($bs -eq $null)) {
                $t = 0
                $b = 0
            }
            if (($ls -eq $null) -and ($rs -eq $null)) {
                $l = 0
                $r = 0
            }
            if ($ts -match ".*active_area_top_offset""`: (\d+).*") {
                $t = [int]$matches[1]
            }
            if ($bs -match ".*active_area_bottom_offset""`: (\d+).*") {
                $b = [int]$matches[1]
            }
            if ($ls -match ".*active_area_left_offset""`: (\d+).*") {
                $l = [int]$matches[1]
            }
            if ($rs -match ".*active_area_right_offset""`: (\d+).*") {
                $r = [int]$matches[1]
            }
            if (($t -eq -1) -or ($b -eq -1) -or ($r -eq -1) -or ($l -eq -1)) {
                FatalError "Can't parse RPU for black bars"
            }
            if ($t + $b + $r + $l -ne 0) {
                #
                # TODO - fix this so that if the borders don't close down to 0, we still crop things
                #
                for ($j = 720; $j -lt $nframes; $j += 720) {
                    $p = ($j*100)/$nframes
                    Write-Progress "Checking... " -Status $j -PercentComplete $p

                    $a = ( &$global:dovi_tool info -i $rpufel_file -f $j)
                    $ts = ($a | Select-string -pattern ".*active_area_top_offset""`: (\d+).*")
                    $bs = ($a | Select-string -pattern ".*active_area_bottom_offset""`: (\d+).*")
                    $ls = ($a | Select-string -pattern ".*active_area_left_offset""`: (\d+).*")
                    $rs = ($a | Select-string -pattern ".*active_area_right_offset""`: (\d+).*")
                    $t1 = -1
                    $b1 = -1
                    $l1 = -1
                    $r1 = -1
                    if ($ts -match ".*active_area_top_offset""`: (\d+).*") {
                        $t1 = [int]$matches[1]
                    }
                    if ($bs -match ".*active_area_bottom_offset""`: (\d+).*") {
                        $b1 = [int]$matches[1]
                    }
                    if ($ls -match ".*active_area_left_offset""`: (\d+).*") {
                        $l1 = [int]$matches[1]
                    }
                    if ($rs -match ".*active_area_right_offset""`: (\d+).*") {
                        $r1 = [int]$matches[1]
                    }
                    if (($t1 -ne $t) -or ($b1 -ne $b)) {
                        Info "Changing borders on top/bottom - ($t, $b) vs ($t1, $b1) at $j"
                        if ((-1 -ne $t1) -and ($t1 -lt $t)) { $t = $t1 }
                        if ((-1 -ne $b1) -and ($b1 -lt $b)) { $b = $b1 }
                    }

                    if (($l1 -ne $l) -or ($r1 -ne $r)) {
                        Info "Changing borders on left/right - ($l, $r) vs ($l1, $r1) at $j"
                        if ((-1 -ne $l1) -and ($l1 -lt $l)) { $l = $l1 }
                        if ((-1 -ne $r1) -and ($r1 -lt $r)) { $r = $r1 }                }

                }
            }
            Info "Borders found on file = ($t, $l, $b, $r)"
            if ((($t + $b) % 2) -ne 0) {
                if ($t -lt $b) { $t += 1 } else { $b += 1}
                Info "Borders modified to ($t, $l, $b, $r)"
            }
            if ((($l + $r) % 2) -ne 0) {
                if ($l -lt $r) { $l += 1 } else { $r += 1}
                Info "Borders modified to ($t, $l, $b, $r)"
            }
            "-top $t -bottom $b -left $l -right $r" | Out-file $borders_file
        }
        else {
            $top = 0; $bottom = 0; $left = 0; $right = 0
        }
    }
    else {
        Warning "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Warning "HDR10+ to DV borders are not going to be correct - check"
        Warning "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }

    #
    # if -mel is set, set $dv to 8 to stop all FEL processing
    #
    if ((7 -eq $dv) -and $mel) {
        $dv = 8
    }
    #
    # For Dolby 7, we need to create a ProRes file to calculate Maxcll
    #
    if ((7 -eq $dv) -or $calc_maxcll) {
        #
        # Create Index file
        #

        if (-not (Test-Path $bl_index -PathType Leaf)) {
            & $global:ffmsindex -f $bl_file $bl_tmpindex
            if ($LastExitCode -eq 0) {
                Rename-Item $bl_tmpindex $bl_index
            }
        }
        if (7 -eq $dv) {
            if (-not (Test-Path $el_index -PathType Leaf)) {
                & $global:ffmsindex -f $el_file $el_tmpindex
                if ($LastExitCode -eq 0) {
                    Rename-Item $el_tmpindex $el_index
                }
            }
        }
    }
    #
    # For type 9, we don't need to do this
    #
    if (9 -ne $dv) {
        #
        # Modify the RPU depending on the cropping situation
        #
        "{"                         | Out-File $p8_json
        "   ""mode"": 2,"           | Out-File -Append $p8_json
        "   ""remove_cmv4"": false" | Out-File -Append $p8_json
        "}"                         | Out-File -Append $p8_json

        $edit = $p8_json
        if ($t + $b + $l + $r -ne 0) {
            "{"                             | Out-File $crop_json
            "    ""mode"": 2,"              | Out-File -Append $crop_json
            "    ""active_area"": {"        | Out-File -Append $crop_json
            "        ""crop"": false,"      | Out-File -Append $crop_json
            "        ""presets"": ["        | Out-File -Append $crop_json
            "            {"                 | Out-File -Append $crop_json
            "                ""id"": 0,"    | Out-File -Append $crop_json
            "                ""left"": 0,"  | Out-File -Append $crop_json
            "                ""right"": 0," | Out-File -Append $crop_json
            "                ""top"": 0,"   | Out-File -Append $crop_json
            "                ""bottom"": 0" | Out-File -Append $crop_json
            "            }"                 | Out-File -Append $crop_json
            "        ],"                    | Out-File -Append $crop_json
            "        ""edits"": {"          | Out-File -Append $crop_json
            "            ""all"": 0"        | Out-File -Append $crop_json
            "        }"                     | Out-File -Append $crop_json
            "    }"                         | Out-File -Append $crop_json
            "}"                             | Out-File -Append $crop_json
            $edit = $crop_json
        }

        if (-not (Test-Path $rpup8_file -PathType Leaf)) {
            & $global:dovi_tool editor -i $rpufel_file -j $edit --rpu-out $rpup8_file
            if ($LastExitCode -ne 0) {
                Remove-File $rpup8_file
                FatalError "Creating P8 RPU file failed"
            }
        }
    }

    $a = (& $global:dovi_tool info -s $rpup8_file)
    $a | Out-File $rpu_info_file

    #
    # Calculate $mdl and $mdl-min if we have Dolby Vision
    #
    if (0 -ne $dv) {
        if (0 -eq $use_mdl[1]) {
            FatalError "No mastering display luminance value"
        }
    }
    #
    # If we've overridden the MaxCLL, there's no reason to go through all the following
    # to calculate it
    #
    if ($false -eq $ov_maxcll) {
        if (7 -eq $dv) {
            $file_to_encode = $avs_file
            #
            # Create avs_file
            #
            "SetFilterMTMode(""DoViBaker"",2)"                                  | Out-File $avs_file
            "bl = FFMpegSource2(""$bl_file"", cachefile=""$bl_index"")"         | Out-File -Append $avs_file
            if (0 -ne $trim) { "bl = bl.Trim(0, " + [string]($trim - 1) + ")"   | Out-File -Append $avs_file }
            "el = FFMpegSource2(""$el_file"", Cachefile=""$el_index"")"         | Out-File -Append $avs_file
            if (0 -ne $trim) { "el = el.Trim(0, " + [string]($trim - 1) + ")"   | Out-File -Append $avs_file }
           "DoviBaker(bl, el)"                                                  | Out-File -Append $avs_file

            if (($t -ne 0) -or ($b -ne 0) -or ($l -ne 0) -or ($r -ne 0)) {
                "Crop($r, $t, -$l, -$b)"                                        | Out-File -Append $avs_file
            }
            "z_ConvertFormat(pixel_type=""YUV420P10"",colorspace_op=""rgb:st2084:2020:full=>2020ncl:st2084:2020:limited"",dither_type=""error_diffusion"",resample_filter=""spline36"",resample_filter_uv=""spline36"",chromaloc_op=""left=>top_left"")" | Out-File -Append $avs_file
            "Prefetch(6)"                                                       | Out-File -Append $avs_file

            #
            # Create ProRes AVS File
            #
            "SetFilterMTMode(""DoViBaker"",2)"                                  | Out-File $avs_prores_file
            "bl = FFMpegSource2(""$bl_file"", cachefile=""$bl_index"")"         | Out-File -Append $avs_prores_file
            if (0 -ne $trim) { "bl = bl.Trim(0, " + [string]($trim - 1) + ")"   | Out-File -Append $avs_prores_file }
            "el = FFMpegSource2(""$el_file"", Cachefile=""$el_index"")"         | Out-File -Append $avs_prores_file
            if (0 -ne $trim) { "el = el.Trim(0, " + [string]($trim - 1) + ")"   | Out-File -Append $avs_prores_file }
            "DoviBaker(bl, el)"                                                 | Out-File -Append $avs_prores_file

            if (($t -ne 0) -or ($b -ne 0) -or ($l -ne 0) -or ($r -ne 0)) {
                "Crop($r, $t, -$l, -$b)"                                        | Out-File -Append $avs_prores_file
            }
            "z_ConvertFormat(pixel_type=""YUV422P10"",colorspace_op=""rgb:st2084:2020:full=>2020ncl:st2084:2020:limited"",dither_type=""error_diffusion"",resample_filter=""spline36"",resample_filter_uv=""spline36"",chromaloc_op=""left=>top_left"")" | Out-File -Append $avs_prores_file
            "Prefetch(6)"                                                       | Out-File -Append $avs_prores_file
        }
        elseif ($calc_maxcll) {
            "FFMpegSource2(""$bl_file"", cachefile=""$bl_index"")"              | Out-File $avs_prores_file
            if (($t -ne 0) -or ($b -ne 0) -or ($l -ne 0) -or ($r -ne 0)) {
                "Crop($r, $t, -$l, -$b)"                                        | Out-File -Append $avs_prores_file
            }
            "Prefetch(6)"                                                       | Out-File -Append $avs_prores_file
        }
        #
        # If we need to calculate maxcll, set things up
        #
        if ((7 -eq $dv) -or $calc_maxcll) {
            #
            # Create ProRes File if maxcll has not already been calculated
            #
            if (-not (Test-Path $maxcll_file -PathType Leaf)) {
                if (-not (Test-Path $mov_file -PathType Leaf)) {
                    $files = Get-ChildItem $mov_pieces
                    if ($files.Count -eq 0) {
                        & $global:ffmpeg -i $avs_prores_file -c:v prores_ks -profile:v 3 -vendor ap10 -qscale:v $qscale -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -pix_fmt yuv422p10le -an -y $movtmp_file
                       if ($LastExitCode -ne 0) {
                            FatalError "Baking FEL failed with exit code $LastExitCode"
                        }
                        Rename-Item $movtmp_file $mov_file
                    }

                }
            }
            #
            # Analyze the file, if the analysis doesn't exist
            #
            if (-not (Test-Path $maxcll_file -PathType Leaf)) {
                $cp = Search_video_info $video_info "Mastering display color primaries"
                if ($cp -eq "BT.2020") {
                    switch ($use_mdl[1]) {
                      1000 { $display =  21 }
                      1100 { $display = 21 }
                      2000 { $display = 31 }
                      4000 { $display = 8 }
                      default { FatalError "Unknown Mastering display luminance" }
                    }
                }
                elseif ($cp -eq "Display P3") {
                    switch ($use_mdl[1]) {
                      1000 { $display =  20 }
                      1100 { $display = 20 }
                      2000 { $display = 30 }
                      4000 { $display = 7 }
                      default { FatalError "Unknown Mastering display luminance" }
                    }
                }
                else {
                    FatalError "Can't parse Mastering display color primaries"
                }

                $display = [string]$display

                $fps = Get_Frame_Rate $video_info

                #
                # Split the file into segments if it's one of the files that slows down a lot as time goes on
                #
                if ($false -eq $no_split) {
                    $files = Get-ChildItem $mov_pieces
                    if ($null -eq $files) {
                        & ffmpeg -i $mov_File  -f segment -segment_time 1800 -vcodec copy -reset_timestamps 1 -map 0 $mov_template
                        $files = Get-ChildItem $mov_pieces
                        if ($null -eq $files) { FatalError "Could not create 1 hour pieces of mov file" }
                    }
                }
                else {
                    $files = Get-ChildItem $mov_file
                }


                $i = 0
                $cll = 0; $fall = 0
                foreach ($f in $files) {
                    $xml_file = $xml_base + [string]$i + ".xml"
                    $xml1_file = "Z:" + $xml_file
                    $mov1 = "Z:" + $f.FullName
                    $t = TaskSet
                    $go = "cm_analyze.exe --bda --letterbox 0 0 0 0 --mastering-display $display --analysis-tuning 3 --frame-rate $fps --source-format ""u10 i422 lsb32rev le ycbcr_bt2020 pq bt2020 video"" ""$mov1"" ""$xml1_file"""
                    if (Is_Linux) {
                        $go = "WINEPREFIX=/home/mike/.winecuda " + $t + " wine C:/bin/" + $go
                        Write-Host "Executing $go"
                        & bash -c $go
                    }
                    else {
                        Write-Host "Executing $go"
                        & cmd /c $go
                    }
                    $tmp_maxcll = Get_Analysis_MaxCLL $xml_file
                    if (0 -eq $tmp_maxcll[0]) {
                        FatalError ("Can't parse maxcll (" + (StringIze maxcll) + ")")
                    }

                    if ($tmp_maxcll[0] -gt $cll) { $cll = $tmp_maxcll[0] }
                    if ($tmp_maxcll[1] -gt $fall) { $fall = $tmp_maxcll[1] }

                    $i = $i + 1
                }
                "$cll,$fall" | Out-File $maxcll_file
                $cll = [math]::Ceiling($cll/10)*10
                $fall = [math]::Ceiling($fall/5)*5
                $use_maxcll = @($cll, $fall)

                if ($qscale -ne 1) {
                    Remove-File $mov_file
                }
                $files = Get-ChildItem $mov_pieces
                foreach ($f in $files) { Remove-File $f.FullName }
                $do_l6 = $true
            }
            #
            # Here, the maxcll file exists - however, don't read it if we over-rode it from the command line
            #
            else {
                if (! $ov_maxcll) {
                    $maxcll = [string](Get-Content $maxcll_file)
                    if ($maxcll -match "(\d+),(\d+)") {
                        $a = [int]($matches[1]); $b = [int]($matches[2])
                        $cll = [math]::Ceiling($a/10)*10
                        $fall = [math]::Ceiling($b/5)*5
                        $use_maxcll = @($cll, $fall)
                        $do_l6 = $true
                    }
                    else {
                        FatalError "Can't parse MaxCLL from analysis file ($maxcll)"
                    }
                }
            }
        }
    }
    # For dv 7 or 8, if we overrode maxcll, we need to modify the rpu
    elseif (($dv -eq 7) -or ($dv -eq 8)) {
        $do_l6 = $true
    }

    #
    # Clip $cll so things don't get too dark
    #
    #if ($use_maxcll[0] -gt $use_mdl[1]) {
    #    switch ($use_mdl[1]) {
    #        1000  { if ($use_maxcll[0] -gt 2000) { $use_maxcll[0] = 2000; $do_l6 = $true }}
    #        4000  { if ($use_maxcll[0] -gt 6000) { $use_maxcll[0] = 6000; $do_l6 = $true }}
    #        10000  { if ($use_maxcll[0] -gt 10000) { $use_maxcll[0] = 10000; $do_l6 = $true }}
    #    }
    #}

    if ($do_l6 -and ($no_touchl6 -eq $false)) {
        $mdl = $use_mdl[1]
        $mdl_min = $use_mdl[0]
        $cll = $use_maxcll[0]
        $fall = $use_maxcll[1]
        Info "Use luminance of $mdl,$mdl_min and maxcll of $cll,$fall for the encode pass"

        "{"                                                         | Out-File $l6_json
        " ""level6"": {"                                            | Out-File -Append $l6_json
            " ""max_display_mastering_luminance"": $mdl,"           | Out-File -Append $l6_json
            " ""min_display_mastering_luminance"": $mdl_min,"       | Out-File -Append $l6_json
            " ""max_content_light_level"": $cll,"                   | Out-File -Append $l6_json
            " ""max_frame_average_light_level"": $fall"             | Out-File -Append $l6_json
        " }"                                                       | Out-File -Append $l6_json
        "}"                                                         | Out-File -Append $l6_json
        #
        # Modify the Level 6 information of the RPU
        #
        Remove-File $rpul6_file

        & $global:dovi_tool editor -i $rpup8_file -j $l6_json --rpu-out $rpul6_file
        if ($LastExitCode -ne 0) {
            Remove-File $rpul6_file
            FatalError "Creating L6 RPU file failed"
        }

        $use_rpu = $rpul6_file
    }
    else {
        $use_rpu = $rpup8_file
    }
}
# For non-dv - we only do cropping on request
if ((0 -eq $dv) -or (9 -eq $dv)) {
    $t = $top; $b = $bottom; $l = $left; $r = $right
}
#
# If $dv is not FEL, then we have to add the crop into the ffmpeg filters, since we're not using an avs file
#
if (7 -ne $dv) {
    if (($t -ne 0) -or ($b -ne 0) -or ($l -ne 0) -or ($rt -ne 0)) {
        $t="crop=" + [string]($width - $l - $r) + ":" + [string]($height - $t - $b) + ":$l" + ":$t"
        if ($filter -ne "") { $filter += "," }
        $filter += $t
    }
}

if ($prep) {
    FatalError "Prep complete"
}

if ($filter -ne "") {
    $args_filter = @("-filter:v", """$filter""")
}

$args_ffmpeg = @("-probesize", "100MB", "-i", """$file_to_encode""", "-an", "-pix_fmt", "yuv420p10le", "-f", "yuv4mpegpipe")

$args_ffmpeg += $args_filter
$args_ffmpeg += $args_ffmpeg_extra

$args_ffmpeg += @("-strict", "-1", "-")


$args_enc = Create_hevc_encode_std_parms $tune $video_info $Threads $No_bt709 $use_maxcll


if (-not $No_specials) {
    $args_enc += Create_hevc_encode_modified_parms
    if (( -not $No_slower_mods) -and ($preset -eq "slower")) {
        $args_enc += Create_hevc_encode_slower_parms $amp
    }
}
$arg = @("--preset", $Preset, "--crf", $Crf)

if ($Inter -ne 0) {
    $arg += @("--nr-inter", [string]$Inter)
}

if ($avx512) {
    $arg += @("--asm", "avx512")
}

if (($Noise -eq "none") -and ($Crf -le 19) -and ($Inter -eq 0) -and ($Tune -ne "grain")) {
    $arg += @("--psy-rdoq", "1.5")
}

$arg += $args_enc
$arg += $args_spcl

$output_tmp = $output_enc_file + ".tmp.hevc"

$arg += @("--input", "-", "--y4m", "--output", """$output_tmp""", "2`>`&1")

if (Test-Path -Path $output_tmp -PathType Leaf) {
    if ($false -eq $force_encode) {
        FatalError "Temp file $output_tmp exists - possibly already being encoded"
    }
}


if (-not (Test-Path -Path $output_mkv  -PathType Leaf) ) {

    if (-not (Test-Path -Path $output_enc_file -PathType Leaf) ) {
        Info "Beginning hevc encoding"
        $ok = $false
        try {
            $n = $global:null_output
            $t = TaskSet
            [string]$go = $t + $global:ffmpeg + " " + [string]$args_ffmpeg + " 2> $n | " + $t + $x265  + " " + [string]$arg
            Write-Output $go
            if (Is_Windows) {
                & cmd /c $go
            }
            else {
                & bash -c $go
                }
            if ($LASTEXITCODE -ne 0) {
                FatalError "Compile failed with exit code $LASTEXITCODE"
            }
            Rename-Item $output_tmp $output_enc_file
            $ok = $true
        }
        finally {
            if ($ok -eq $false) {
                $a = Find_Process $x265 $output_mkv
                if ($a -ne $null) {
                    $a.Kill()
                }
                $a = Find_process $global:ffmpeg file_to_encode
                if ($a -ne $null) {
                    $a.Kill()
                }
                Remove-File $output_tmp
                throw
            }
        }
    }
    #
    # Here - we have to mux in the Dolby Video information
    #

    if ($mux_rpu) {

        if (-not( Test-Path -Path $dv_muxed_file -PathType Leaf)) {
            Info "Muxing EL_RPU ($use_rpu) with HEVC"
            #
            # If it's an rpu (i.e. dvhe 08.06), we must reinject the rpu - muxing the el_rpu doesn't get the
            # video flagged as DolbyVision for some reason
            #
            Dovi_inject $output_enc_file $use_rpu $dv_muxed_file

        }
        $output_use_enc = $dv_muxed_file

    }
    else {
        $output_use_enc = $output_enc_file
    }
    $l = $false
    try {
        $l = Lock_disk $input_file
        if (($colorspace -eq "BT.709") -or (($colorspace -eq "") -and ($No_bt709 -eq $false))) {
            mkv_remux.ps1 "$output_use_enc" "$input_file" "$output_mkv" -bt709 -all
        }
        elseif (0 -ne $use_maxcll[0]) {
            $tmp = [string]($use_maxcll[0]) + "," + [string]($use_maxcll[1])
            mkv_remux.ps1 "$output_use_enc" "$input_file" "$output_mkv" -all
        }
        else {
            mkv_remux.ps1 "$output_use_enc" "$input_file" "$output_mkv" -all
        }
    }
    finally {
        Unlock_disk $l
    }
    if (("" -eq $group) -or ("nogroup" -eq $group)) { $group = "none" }
    & video.ps1 retitle "$output_mkv" -group $group
}










