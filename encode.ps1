param (
 [Parameter(Mandatory = $true, Position = 0)]
 [string]$Input_name,
 [Parameter(Mandatory = $false)]
 [string]$Output = "",                # Output file base name, if specified
 [int]$Crf=0,                         # CRF Value
 [string]$Noise="none",               # Type of denoising desired
 [ValidateSet('veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'default')]
   [string]$Preset="default",         # What compiler preset to use
 [ValidateSet('none', 'animation', 'grain')]
   [string]$Tune="none",              # -tune parameter for x264 or x265
 [switch]$Avc=$false,                 # use AVC instead of HEVC
 [switch]$Mel,                        # Force mel for dolby vision
 [switch]$No_bt709=$false,			  # Don't set bt709 if it's not BT2020
 #
 [switch]$Amp=$false,                 # $true if we want to use --amp in hevc slower
 [switch]$No_slower_mods = $false,    # Turn of special handling for slower hevc preset
 [int]$Inter=0,
 [switch]$No_specials = $false,       # Turn of all special handling
 [string]$Filters = "",               # Extra filters for ffmpeg (e.g. scale-320:240,setsar=1:1)
 #
 [switch]$Tff=$false,
 [switch]$Bff=$false,
 [switch]$Yadif=$false,
 [switch]$Nnedi3=$false,
 [int]$Kerndeint=-1, 
 #
 [string]$Aignore,                    # audio tracks to ignore
 [string]$Signore,                    # subtitle tracks to ignore
 [string]$Track="0",                  # video track (0 is normally correct)
 #
 [string]$Start="",                   # set start of video to use (only if $length -ne 0
 [int]$Length=0,                      # length in seconds of clip to encode
 #
 [string]$Threads="std",              # std means our reduced number of threads, default means x265 default. none is none
 [switch]$Extra,
 [switch]$test_crf,                   # encode 5% of the video to see approx bitrate for given parameters.
 [switch]$Notest = $false
 )
 
 Import-Module MediaOS, MediaUtils

 $level = "f"               # This is the "level" of our encodes

 #
 # Set up important variables
 #

 $args_spcl = @()

 $args_filter = @()
 $args_ffmpeg_extra = @()
 #
 # Don't remux if we're just testing crf
 #
 if ($test_crf) {
     $remux = $false
 }
 else {
     $remux = $true
 }
 $dv = $false

 #
 # Insure the input file exists
 #
 if (-not (Test-Path -Path $Input_name -PathType Leaf) ) { 
    Write-Host -ForegroundColor Red "ERROR: File '$Input_name' does not exist!"
    Exit(3)
}
$input_file = gci $Input_name
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
if ($video_info -eq $null) {
    Write-Host -ForegroundColor Red "ERROR: This is not a recognized video file"
    Exit(1)
}
if ($video_info["Video #1"] -ne $null) {
    Write-Host -ForegroundColor Red "ERROR: There is more than one video track in this file"
    Exit(1)
}

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
    elseif ($avc) {
        $crf = 18
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
# Add denoising information
#

$filter = ""
$nl = $true
$intex = ""

if ($Noise -match "vague(\d)([\+\-]?)") {
    $nl = $false
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
        Write-error("++++ ERROR ++++ Unknown -noise value = $Noise")
        Exit(1)
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
elseif ($Noise -eq "nlmeans0") {
    $extra_info += "n0"
    $filter = "nlmeans=1.0:7:5:3:3"
}
elseif ($Noise -eq "nlmeans1") {
    $extra_info += "n1"
    $filter = "nlmeans=1.5:7:5:3:3"
}
elseif ($Noise -eq "nlmeans2") {
    $extra_info += "n2"
    $filter = "nlmeans=3.0:7:5:3:3"
}
elseif ($Noise -eq "nlmeans3") {
    $extra_info += "n3"
    $filter =  "nlmeans=6.0:7:5:3:3"
}
elseif ($Noise -eq "none") {
    $nl = $false
}
else {
    Write-error("++++ ERROR ++++ Unknown -noise value = $Noise")
    Exit(1)
}


if ($nl -and (-not $Avc) ) {
    Write-error("++++ ERROR ++++ Nlmeans filter must be used with AVC (8-bit internal path)") 
    Exit(1)
}
if (-not $Avc) {
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
}
else {
    if ($inter -ne 0) {
        Write-Host -ForegroundColor red "Warning: Ignoring 'Inter' information ++++"
    }
}



if (-not $Avc) {
    $extra_info += $level
}
else {
    $extra_info += "_avc"
}

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
    if ($filter -ne "") {
        $filter += ","
    }
    $filter += "yadif"
}
if ($kerndeint -ge 0) {
    if ($filter -ne "") {
        $filter += ","
    }
    $filter += "kerndeint=thresh=" + [string]$kerndeint
}
if ($nnedi3) {
    if ($filter -ne "") {
        $filter += ","
    } 
    $filter += "nnedi=weights=nnedi3_weights.bin"
}
if ($test_crf) {
    if ($filter -ne "") {
        $filter += ","
    }
    $filter += "select=lt(mod(n\,2400)\,120)"
}

if ($filter -ne "") {
    $args_filter = @("-filter:v", $filter)
}



#
# Unfortunately, we can't finalize the $extra_info for hevc until we've looked at the DV information
# We want to add _dv8, _dvm, or _dv depending on the dolby vision situation.
#
$hdr10plus = Video_has_hdr10 $video_info
$dv_info = Video_dv_type $video_info
$duration = Get_video_duration $video_info
$colorspace = Search_video_info $video_info "Color primaries"


if ($colorspace -eq "BT.2020") {
    if ($Avc) {
        Write-Host -ForegroundColor Red "Warning: Encoding BT.2020 video with AVC ++++"
    }
    if ($No_bt709) {
        Write-Host -ForegroundColor Red "Warning: ignoring -no-bt709 switch ++++"
        $no_bt709 = $false
    }
}
else {
    $mel = $false
    if ($colorspace -eq "BT.709") {
        if ($No_bt709) {
            Write-Host -ForegroundColor Red "Warning: Colorspace is coded as BT.709 - ignoring -no-bt709 switch ++++"
            $no_bt709 = $false
        }
    }
}

if ($hdr10plus) {
    Write-Host -ForegroundColor green "INFO: Video has HDR10+ Profile ++++"
}

$dv_auto = $false
$is_rpu = $false
if ($dv_info -ne "") {
    if ($Avc) {
        Write-Host -ForegroundColor Red "Warning: Encoding Dolby-vision with AVC! ++++"
    }
    if ($dv_info -eq "08.06") {
        $mel = $true
        $is_rpu = $true
    }
    elseif ($dv_info -eq "07.06") {
        if (-not $mel) {
            Write-Host -ForegroundColor green "INFO: This file has Dolby Vision on it, handling in auto mode ++++"
            $dv_auto = $true        
        }
    }
    else {
        Write-Host -ForegroundColor Red "ERROR: Can't convert dvhe $dv_info file ++++"
        Exit(1)    
     }
}
#
# Create hash file of all the output files we might need - We'll have to call this again once we've established the final result
#
#
$files_hash = Create_file_names $output_base_name $extra_info $extra_info

$ftmp = $files_hash["sync_ok_file"]
if ((-not $notest) -and (-not (Test-Path -Path $ftmp -PathType Leaf))) {
    Write-Host -ForegroundColor Green "INFO: Testing Sync of mkv file ++++"
    if (-not (Test_Mkv $input_file.FullName)) {
        Write-Host -ForegroundColor Red "ERROR: Sync errors in mkv file - exiting ++++"
        Exit(1)
    }   
    "ok" | Out-file $ftmp
}


if (($colorspace -eq "BT.2020") -or $hdr10plus -or $dv_auto -or $mel) {
    $extr = $files_hash["extr_file"]
    if (-not (Test-Path -Path $extr -PathType Leaf)) {
         Write-Host -ForegroundColor green "INFO: Demuxing video ++++"
         Extract_hevc $track $input_file.FullName $extr    
    }
    $bl_file = $files_hash["bl_file"]
    $el_file = $files_hash["el_rpu_file"]
    #
    # If the file is dv 08.06, you can't extract and reinject the el_rpu - for some reason, nothing flags it as DV if you do that.
    # You must "extract-rpu" and "inject-rpu" to do it, so we add the .bin extension to make it explicit.  Later on, if it's an rpu,
    # we'll do inject-rpu instead of muxing the el_rpu
    #
    if ($is_rpu) {
        $el_file += ".bin"
        $mel = $true
    }
    $dv = $false
    if ($dv_auto -or $mel) {
        if ((-not (Test-Path $bl_file -PathType Leaf)) -or (-not (Test-Path $el_file -PathType Leaf))) {
            Write-Host -ForegroundColor green "INFO: Separating bl and el_rpu layers ++++"
            Extract_dovi_layer $is_rpu $extr $el_file
        }
        $fsize = (Get-Item -Path $el_file).Length
        $brate = ($fsize * 8)/$duration
        $val = [string]([math]::Round(($brate/1MB),2))
        $old_ex = $extra_info
        #
        # 2310000 = 2.2 Mbits
        #
        if ($brate -gt 2310000) {
            if ($dv_auto) {

                Write-Host -ForegroundColor green "INFO: Setting Dolby to _dv, bitrate = $val MB ++++"
                $dv = $true
                $extra_info += "_dv"
            }
            else {
                if ($is_rpu) {
                    Write-Host -ForegroundColor red "WARNING: FEL Dolby-vision as 08.06???? ++++"
                }
                Write-Host -ForegroundColor green "INFO: Setting Dolby to _dvm, bitrate = $val MB ++++"
                $mel = $true
                $extra_info += "_dvm"     
                $is_rpu = $true
                $el_file += ".bin"
                if (-not (Test-Path $el_file -PathType Leaf)) {
                    Write-Host -ForegroundColor green "INFO: Re-separating layers as BL/RPU"
                    #
                    # $bl_file was already created by the previous separate, so we don't want to overwrite it.
                    #
                    Extract_dovi_layer $true $extr $el_file
                }
            }
        }
        else {
            if ($is_rpu) {
                Write-Host -ForegroundColor green "INFO: Setting Dolby to _dv806 for dvhe 08.06 ++++"
                $extra_info += "_dv806"
            }
            else {
                Write-Host -ForegroundColor green "INFO: Setting Dolby to _dv8, bitrate = $val MB ++++"
                $extra_info += "_dv8"
            }
            $mel = $true     
        }
        #
        # Redo the $files_hash (all the input names won't change, but the output ones will have the extra DV info on them now)
        #
        $files_hash = Create_file_names $output_base_name $old_ex $extra_info
    }
    if ($hdr10plus) {
        $json = $files_hash["hdr10_json"]
        if (-not (Test-Path $json -PathType Leaf)) {
            Write-Host -ForegroundColor green "INFO: Create Hdr10+ json file ++++"
            Create_hdr10plus_json_file $extr $json
        }
        $args_spcl += @("--dhdr10-info", """$json""", "--dhdr10-opt")
    }
    if ($dv) {
        $chp = $files_hash["chapter_file"]
        if (-not (Test-Path $chp -PathType Leaf)) {
            Write-Host -ForegroundColor green "INFO: Create chapter file ++++"
            Create_chp_file $el_file $chp
        }
        $args_spcl += @("--qpfile", """$chp""")
    }
    $file_to_encode = $extr
}
else {
    $file_to_encode = $input_file.FullName
}
#
#########################################################################################################
# If it's an AVC file, let's get it out of the way
#########################################################################################################
#
if ($avc) {
    $t = $tune
    if ($t -eq "none") {
        $t = "film"
    }
    $output_mkv = $files_hash["out_file"]
    $output_mkv_enc = $files_hash["tmp3_mkv"]
    $output_mkv_tmp = $output_mkv_enc + ".tmp.mkv"
    if (-not (Test-Path $output_mkv -PathType Leaf) ) {
        if (-not (Test-Path $output_mkv_enc -PathType Leaf) ) {

            $fps = Get_Frame_Rate($video_info)

            $arg = @($global:ffmpeg, "-i", """$file_to_encode""", "-strict", "-1", "-f", "yuv4mpegpipe")
            if ($test_crf) {
                $arg += @("-fps_mode", "drop")
            }
            $arg += $args_filter
            $arg += $args_ffmpeg_extra
            $arg += @("-an", "-sn", "-", "2>", "nul", "|")
            $arg += @($x264, "--demux", "y4m", "--fps", $fps, "--sar", "1:1", "--level", "4.1", "--preset", $preset, "--thread-input", "--threads", "auto")

            if (($colorspace -eq "BT.709") -or ($no_bt709 -eq $false)) {
                $arg += @("--transfer", "bt709", "--colorprim", "bt709", "--colormatrix", "bt709")
            }
            else {
                Write-Host -ForegroundColor red "Warning: File not being encoded as BT.709 +++"
            }

            if ($Tff) {
                $arg += @("--tff")
            }
            elseif ($Bff) {
                $arg += @("--bff")
            }
            $arg += @("--tune", $t, "--crf", $crf, "-o", """$output_mkv_tmp""", "-")
            $go = [string]$arg
            #
            # TODO: Change this over to Start-process or Invoke-Expression
            #
            Write-Output($go)
            if (Is_Windows) {
                & cmd /c $go
            }
            else {
                & bash -c $go
            }
            if ($LASTEXITCODE -ne 0) {
                Exit(1)
            }
            Rename-Item $output_mkv_tmp $output_mkv_enc
        }
        if ( $remux ) {

            if (($colorspace -eq "BT.709") -or ( -not $No_bt709)) {
                mkv_remux.ps1 "$output_mkv_enc" "$input_file" "$output_mkv" -aignore $aignore -signore $signore -bt709 -all
            }
            else {
                mkv_remux.ps1 "$output_mkv_enc" "$input_file" "$output_mkv" -aignore $aignore -signore $signore -all
            }
        }
    }
    Exit(0)
}
#
#########################################################################################################
# Here, its an HEVC file, so it should already be demuxed and ready to go
#########################################################################################################
#

$args_ffmpeg = @("-probesize", "100MB", "-i", """$file_to_encode""", "-an", "-pix_fmt", "yuv420p10le", "-f", "yuv4mpegpipe")
if ($test_crf) {
    $args_ffmpeg += @("-fps_mode", "drop")
}

$args_ffmpeg += $args_filter
$args_ffmpeg += $args_ffmpeg_extra
$args_ffmpeg += @("-strict", "-1", "-")

$args_enc = Create_hevc_encode_std_parms $tune $video_info $Threads $No_bt709

if (-not $No_specials) {
    $args_enc += Create_hevc_encode_modified_parms
    if (( -not $No_slower_mods) -and ($preset -eq "slower")) {
        $args_enc += Create_hevc_encode_slower_parms $amp
    }
}
$tmp = '"' + $output_tmp + '"'
$arg = @("--preset", $Preset, "--crf", $Crf)

if ($Inter -ne 0) {
    $arg += @("--nr-inter", [string]$Inter)
}

if (($Noise -eq "none") -and ($Crf -le 19) -and ($Inter -eq 0) -and ($Tune -ne "grain")) {
    $arg += @("--psy-rdoq", "2.0")
}

$arg += $args_enc
$arg += $args_spcl
$output_enc = $files_hash["enc_file"]
$output_tmp = $output_enc + ".tmp.hevc"
$arg += @("--input", "-", "--y4m", "--output", """$output_tmp""", "2`>`&1")
    
$output_mkv = $files_hash["out_file"]

if (-not (Test-Path -Path $output_mkv  -PathType Leaf) ) {

    if (-not (Test-Path -Path $output_enc -PathType Leaf) ) {
        Write-Host -ForegroundColor green "INFO: Beginning hevc encoding"
        [string]$go = $global:ffmpeg + " " + [string]$args_ffmpeg + " 2> nul | " + $x265  + " " + [string]$arg
        echo $go
        if (Is_Windows) {
            & cmd /c $go
        }
        else {
            & bash -c $go
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor Red "ERROR: Compile failed with exit code $LASTEXITCODE +++"
            Exit(1)
        }
        Rename-Item $output_tmp $output_enc
    }
    #
    # Here - we have to mux in the Dolby Video information
    #
    if ($test_crf -eq $false) {
        if ($mel -or $dv) {
            $reg = $files_hash["dv_file"]
            if (-not( Test-Path -Path $reg -PathType Leaf)) {
                Write-Host -ForegroundColor green "INFO: Muxing EL_RPU with HEVC ++++"
                #
                # If it's an rpu (i.e. dvhe 08.06), we must reinject the rpu - muxing the el_rpu doesn't get the
                # video flagged as DolbyVision for some reason
                #
                if ($is_rpu) {
                    Dovi_inject $output_enc $el_file $reg
                }
                else {
                    Dovi_mux $dv $output_enc $el_file $reg
                }
            }
            $output_use_enc = $reg

        }
        else {
            $output_use_enc = $output_enc
        }

        if ( $remux ) {
            if (($colorspace -eq "BT.709") -or (($colorspace -eq "") -and ($No_bt709 -eq $false))) {
                mkv_remux.ps1 "$output_use_enc" "$input_file" "$output_mkv" -aignore $aignore -signore $signore -bt709 -all
            }
            else {
                mkv_remux.ps1 "$output_use_enc" "$input_file" "$output_mkv" -aignore $aignore -signore $signore -all
            }
            & RetitleMkv.ps1 "$output_mkv"
        }
    }
}