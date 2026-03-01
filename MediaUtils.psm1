
Import-Module MediaOS, SystemUtils


function File_needs_lock {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $file
    )
    $tmp = Get-ChildItem $file
    $f = $tmp.FullName
    if ($f.StartsWith($global:lock_dir)) {
        return $true
    }
    return $false
}

function Lock_disk {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $file
    )
    if ((File_needs_lock $file)) {
        $did1 = $false
        $tmpfile = $global:lock_file + "." + [system.io.path]::GetRandomFileName()
        $file | Out-File $tmpfile
        while ($true) {
            try {
                Rename-Item $tmpfile $global:lock_file -ErrorAction Stop
                if ($true -eq $did1) {
                    Write-Host "Grabbed Lock file - movin' on...."
                }
                return $true
            } catch {
                if ($false -eq $did1) {
                    Write-Host "Waiting on Lock file...."
                }
                $did1 = $true
                $a = Get-Random -Minimum 5 -maximum 15
                Start-Sleep $a
            }
        }

    }
    return $false
}

function Unlock_disk {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [switch] $did_lock
    )
    if ($did_lock -ne $false) {
        Remove-File $global:lock_file
    }
}

#
#
#
function Create_Media_info_hash {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Array] $Lines
    )
    $hash = @{}
    $key = ""
    $state = 0
    $values = @{}
    foreach ($line in $Lines) {
        if ( $state -eq 0 ) {
            if ($line.Length -eq 0) {
                continue
            }
            if ( $line -match "^[a-zA-Z]+$" ) {
                $key = $line
                $state = 1
            }
            elseif ( $line -match "^[a-zA-Z]+ #\d+$" ) {
                $key = $line
                $state = 1
            }
            else {
                FatalError "Unexpected line ($line)"
            }
        }
        else {
            if ($line.Length -eq 0) {
                $hash.Add($key, $values)
                $values = @{}
                $key = ""
                $state = 0
                continue
            }
            if ($line -match "^(.*)[ ]+: (.*)$") {
                $a = $matches[1].Trim()
                $b = $matches[2].Trim()
                $values.Add($a,$b)
            }
            else {
                FatalError "Unexpected line for key $key ($line)"
            }
        }
    }
    if ($key -ne "") {
        $hash.Add($key, $values)
    }
    return $hash
}


#
# Use Media_Info cli to get information about theprogram
#
function Get_Media_info {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Filename
    )
    $OutputEncoding = [console]::OutputEncoding = [console]::InputEncoding = New-Object System.Text.UTF8Encoding
    $use = $global:mediainfo + " """ + $Filename + """ 2>&1"
    $info = (Invoke-Expression $use )
    $hash = Create_Media_info_hash $info
    return $hash
}

Function Search_media_info {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Info,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Section,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Value
    )
    $hash = $Info[$Section]
    if ($hash -eq $null) {
        return $null
    }
    $val = $hash[$Value]
    if ($val -eq $null) {
        return ""
    }
    return $val
}

Function Search_video_info {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Info,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Value
    )
    return Search_media_info $Info "Video" $Value
}

#
# Escape &s in filenames going to the cmd line
# (probably need to do @ as well, but haven't run
#  into any of those yet)
#
function Fix_Cmd_Filename {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$name
    )
    return $name -replace '[&]', '^$&'
}
#
# Take a filename and remove extraneous information to create a base file name
#
Function Strip_File_Name {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Filename
    )
    $input_file = gci $Filename
    $output_base_name = $input_file.BaseName
    if ($output_base_name -match "(.+) Remux-[\d]+p.*") {
       $output_base_name = $matches[1]
    }

    if ($output_base_name -match "(.+) \(Bluray-[\d]+p Remux\).*") {
       $output_base_name = $matches[1]
    }
    if ($output_base_name -match "(.+) \(Bluray-[\d]+p Remux Proper\).*") {
       $output_base_name = $matches[1]
    }
    if ($output_base_name -match "(.+)\.bray_dv.?") {
       $output_base_name = $matches[1]
    }
    return $output_base_name
}
#
# Return the main encoding directory for a specific file
#
function Get_encode_dir {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Output_name
    )
    $f = $global:enc_dir + $Output_name + $global:separator
    return $f
}

#
# Create a hash file of the various file names we'll use
#
Function Create_File_Names {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $video_info,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Output_name,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Ext_extra,
        [Parameter(Mandatory = $true, Position = 3)]
        [string] $Ext_extra_dv
    )
    $ext = "hevc"
    if ((Search_video_info $video_info "Format") -eq "AVC") {
        $ext = "h264"
    }

    $hash = @{}
    $dir = Get_encode_dir $Output_name
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType "directory" | Out-Null
    }
    #
    # Files that don't depend on DV information
    #

    $hash.Add("sync_ok_file", $dir + $Output_name + ".SyncOK.txt")
    $hash.Add("hdr10_json", $dir + $Output_name + ".hdr10p.json")
    $hash.add("extr_file", $dir + $Output_name + ".extr.$ext")
    $hash.Add("bl_file", $dir + $Output_name + ".bl.$ext")
    $hash.add("el_rpu_file", $dir + $Output_name + ".el_rpu.$ext")
    $hash.add("chapter_file", $dir + $Output_name + ".chp")
    $hash.add("tmp1_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp1.mkv")
    $hash.add("tmp2_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp1_t00.mkv")
    $hash.add("tmp3_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp3.mkv")
    $hash.add("enc_file", $dir + $Output_name + "." + $Ext_extra + ".enc.$ext")
    $hash.add("baked_file", $dir + $Output_name + ".extr.hevc.mov")
    $hash.add("rpu_file", $dir + $Output_name + ".rpu.bin")
    $hash.add("borders_file", $dir + $Output_name + ".borders.txt")
    $hash.Add("base_name", $dir + $Output_name)
    #
    # Files that depend on DV information
    #
    $hash.add("dv_file", $dir + $output_name + "." + $Ext_extra_dv + ".dv1.$ext")
    $hash.add("out_file", $global:mux_dir + $Output_name + "." + $Ext_extra_dv + ".mkv")
    return $hash
}

#
# This section is for simpler parsing of media info
#
 Function Get_video_width {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "Width"
    if ( $v -match "(\d) (\d\d\d) pixels") {
        $r = $matches[1] + $matches[2]
        return [int]$r
    }
    if ( $v -match "(\d\d\d) pixels") {
        $r = $matches[1]
        return [int]$r
    }
    return 0
}

Function Get_video_height {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "Height"
    if ( $v -match "(\d) (\d\d\d) pixels") {
        $r = $matches[1] + $matches[2]
        return [int]$r
    }
    if ( $v -match "(\d\d\d) pixels") {
        $r = $matches[1]
        return [int]$r
    }
    return 0
}
Function Get_video_original_height {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "Original height"
    if ( $v -match "(\d) (\d\d\d) pixels") {
        $r = $matches[1] + $matches[2]
        return [int]$r
    }
    if ( $v -match "(\d\d\d) pixels") {
        $r = $matches[1]
        return [int]$r
    }
    return 0
}

function Video_has_hdr10 {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "HDR format"
    if ($v -match ".*HDR10\+ Profile .+") {
        return $true
    }
    return $false
}

function Video_dv_type {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "HDR format"
    if ($v -match "Dolby Vision.+, dvhe\.(\d\d\.\d\d),.*") {
        return $matches[1]
    }
    return ""
 }

 function Get_video_duration {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $v = Search_video_info $hash "Duration"
    if ($v -match "([\d]+) h ([\d]+) min") {
        return ([int]$matches[1])*3600 + [int]$matches[2]*60
    }
    elseif ($v -match "([\d]+) min ([\d]+) s") {
        return ([int]$matches[1])*60 + [int]$matches[2]
    }
    return 0
}

function Get_Frame_Rate {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $hash
    )
    $r = Search_video_info $hash "Frame rate"
    if ($r -match " [\d\.]+ \(([\d\/]+)\) .*FPS") {
        $res = $matches[1]
    }
    elseif ($r -match "([\d\.]+) .*FPS") {
        $res = $matches[1]
    }
    else {
        return ""
    }
    if ($res -eq "23.976") {
        $res = "24000/1001"
    }
    return [string]$res
}

function Get_video_interlacing {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $i = Search_video_info $media_info "Scan type, store method"
    if ($i -eq "Interleaved fields") {
        $j = Search_video_info $Media_info "Scan order"
        if ($j -eq "Top Field First") {
            return "tff"
        }
        if ($j -eq "Bottom Field First") {
            return "bff"
        }
        FatalError "Can't determine interlacing field order: $j"
    }
    return ""
}

function Get_group_from_title {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $video_info
    )
    $a = Search_media_info $i "General" "Movie name"
    if ($a -match ".*\[(.*)\]$") {
        return $matches[1]
    }
    return ""
}

function Is_Hybrid {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $input_file
    )
    $a = ($input_file -split '-')
    if ($a.Count -gt 1) {
        $b = $a.Count - 1
        if ($a[$b] -match "(.*)\.mkv") {
            $c = $matches[1]
            if ($c -like "*Hybrid*") {
                return $true
            }
        }
    }
    return $false
}

function Get_group {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $input_file
    )
    $a = ($input_file -split '-')
    if ($a.Count -gt 1) {
        $b = $a.Count - 1
        if ($a[$b] -match "(.*)\.mkv") {
            $c = $matches[1]
            if (($c -like "*Hybrid*") -or ($c -like "*Good*") -or ($c -like "* Cut") -or ($c -like "Extended") -or ($c -like "Theatrical") -or ($c -like "Unrated") -or ($c -like "Openmatte")) {
                if ($a.Count -gt 2) {
                    $c = $a[$b - 1]
                }
                else {
                    return "none"
                }
            }
            if (($c -like "*Remux*") -or ($c -match ".*\(\d+\).*") -or ($c -match ".*\d+p.*")) {
                return ""
            }
            return $c
        }

    }
    return "none"
}
#
# Functions to help with encoding hevc
#
function Create_hevc_pools_and_threads {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object]$Media_info,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Threads
    )
    if ($Threads -eq "std") {
        $a = Get_video_width $Media_info
        #
        # TODO: This doesn't work for Linux
        #
        if (Is_Windows) {
            $cs = get-ciminstance -Verbose:$false -class Win32_ComputerSystem
            if ( $cs.NumberOfLogicalProcessors -gt 12 ) {
                return @("--pools", "12", "--frame-threads", "4", "--wpp")
            }
        }
        else {
            return @("--pools", "12", "--frame-threads", "4", "--wpp")
        }
    }
    elseif ($Threads -eq "default") {
        return @("--wpp")
    }
    elseif ($Threads -ne "none") {
        if ($Threads[0] -eq "+") {
            return @("--pools", $Threads.TrimStart("+"), "--wpp", "--pmode")
        }
        return @("--pools", $threads, "--wpp")
    }
    return @()
}

function Create_hevc_encode_modified_parms {
    $DebugPreference = 'Continue'
    #
    # Per http://forum.doom9.net/showthread.php?t=168814&page=430
    #
    $res = @("--selective-sao","2","--rskip","2", "--rskip-edge-threshold", "3")
    $res += @("--limit-sao")

    return $res
}

function Create_hevc_encode_slower_parms {
    param (
        [switch]$amp
    )
    $DebugPreference = 'Continue'

    $res += @("--limit-refs", "3", "--rd", "4")
    if ($amp) {
        $res += @("--amp")
    }
    else {
        $res += @("--no-amp")
    }
    return $res
}

function Create_hevc_encode_std_parms {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Tune,
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Object]$Media_info,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$Threads,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$No_bt709,
        [Parameter(Mandatory = $true, Position = 4)]
        [System.Object]$maxcll
    )

    $DebugPreference = 'Continue'

    $res = @()

    if ( ($tune -ne "none") -and ($tune -ne "film") ) {
         $res += @("--tune", $tune)
    }

    $res += Create_hevc_pools_and_threads $mediaInfo $threads

    $res += @("--profile", "main10")
    $colorspace = Search_video_info $Media_info "Color primaries"

    if ($colorspace -eq "BT.2020") {
        $res += @( "--repeat-header", "--vbv-bufsize", "60000", "--vbv-maxrate", "48000", "--colorprim", "bt2020", "--colormatrix", "bt2020nc")

        $type = Get_Chromaloc_Type $Media_info

        if ( $type -ge 0 ) {
            $tmp = [string]$type
            $res += @("--chromaloc", $tmp)
        }
        else {
            Write-Host -ForegroundColor red "WARNING: --chromaloc info missing ++++"
        }

        $luminance = Get_mediainfo_luminance $Media_info
        if (0 -eq $luminance[1]) {
            Write-Host -ForegroundColor red "WARNING: --luminance is missing ++++"
        }

        $display = Get_Display_colors  $Media_info
        if ($display -eq "") {
            Write-Host -ForegroundColor red "WARNING: Display is not P3 or BT2020 or spelled out ++++"
        }

        if ((0 -ne $luminance[1]) -and ($display -ne "")) {
            $tmp = [string](10000*$luminance[1]) + "," + [string]($luminance[0])
            $res += @("--transfer", "smpte2084", "--hdr10", "--hdr10-opt")
            $res += @("--master-display", """${display}L(${tmp})""")
        }
        else {
            $res += @("--transfer", "bt2020-10")
        }
        if (0 -eq $maxcll[0] ) {
            $maxcll = Get_mediainfo_maxcll $Media_info
        }

        if (0 -ne $maxcll[0]) {
            $tmp = [string]($maxcll[0]) + "," + [string]($maxcll[1])
            $res += @("--max-cll", $tmp, "--cll")
        }
        else {
            Write-Host -ForegroundColor red "WARNING: -maxcll is missing ++++"
        }
    }
    else {
        $i = Get_video_interlacing $Media_info
        if ($i -ne "") {
            $res += @("--interlace", $i)
        }
        #
        # Better banding characteristics when encoding from 8-bit according to x265 documentation
        #
        if (($Tune -ne "grain") -or ((Get_video_width $Media_info) -lt 1921)) {
            $res += @("--aq-mode", "3")
        }
        $res += @("--repeat-header", "--vbv-bufsize", "45000", "--vbv-maxrate", "48000", "--hdr")
        if (($colorspace -eq "BT.709") -or ($No_bt709 -eq $false) ) {
            $res += @("--colorprim", "bt709", "--transfer", "bt709", "--colormatrix", "bt709")
        }
    }

    $rate = Get_Frame_Rate $Media_info
    if ($rate -eq "") {
        FatalError "Can't get frame rate"
    }

    $res += @( "--fps", $rate, "--sar", "1:1", "--keyint", "120")
    return $res
}

function Get_Chromaloc_Type {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $r = Search_video_info $Media_info "Chroma subsampling"
    if ($r -match "4:2:0 \(Type (\d)\)") {
        return [int]$matches[1]
    }
    return -1
 }


 function Get_display_colors {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $r = Search_video_info $Media_info "Mastering display color primaries"

    if ($r -eq "BT.2020") {
        return "G(8500,39850)B(6550,2300)R(35400,14600)WP(15635,16450)"
    }
    if ($r -eq "Display P3") {
        return "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)"
    }
    #if ($r -match "R: x=0.(\d\d\d\d\d\d) y=0.(\d\d\d\d\d\d), G: x=0.(\d\d\d\d\d\d) y=0.(\d\d\d\d\d\d), B: x=0.(\d\d\d\d\d\d) y=0.(\d\d\d\d\d\d), White point: x=0.(\d\d\d\d\d\d) y=0.(\d\d\d\d\d\d)") {
    #        $res =  "G(" + (([int]$matches[3])/20).ToString() + "," + (([int]$matches[4])/20).ToString() + ")"
    #        $res += "B(" + (([int]$matches[5])/20).ToString() + "," + (([int]$matches[6])/20).ToString() + ")"
    #        $res += "R(" + (([int]$matches[1])/20).ToString() + "," + (([int]$matches[2])/20).ToString() + ")"
    #        $res +="WP(" + (([int]$matches[7])/20).ToString() + "," + (([int]$matches[8])/20).ToString() + ")"
    #        break
    #    }

    return ""
}


 function Get_mediainfo_luminance {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $r = Search_video_info $Media_info "Mastering display luminance"
    if ($r -match "min\: 0\.(\d\d\d\d) cd\/m2, max\: (\d+) cd\/m2") {
        $first = [int]$matches[1]
        $second = [int]$matches[2]
        return @($first, $second)
    }
    if ("" -ne $r) {
        return $r
    }
    return @(0,0)
 }

 function Get_mediainfo_maxcll_original {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $got1 = $false
    $r1 = Search_video_info $Media_info "MaxCLL_Original"
    if ($r1 -ne "") {
        if ($r1 -match "(\d+) cd\/m2") {
            $v1 = [int]$matches[1]
            return $v1
        }
    }
    return 0
 }

 function Get_mediainfo_maxcll {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $got1 = $false
    $got2 = $false
    $r1 = Search_video_info $Media_info "Maximum Content Light Level"
    $r2 = Search_video_info $Media_info "Maximum Frame-Average Light Level"
    if (($r1 -ne "") -and ($r2 -ne "")) {
        if ($r1 -match "(\d+) cd\/m2") {
            $v1 = [int]$matches[1]
            if ($r2 -match "(\d+) cd\/m2") {
                $v2 = [int]$matches[1]
                return @($v1, $v2)
            }
        }
        $a = Get_mediainfo_maxcll_original $Media_info
        if ($a -ne 0) {
            if ($r1 -match "(\d+)") {
                $v1 = [int]$matches[1]
                if ($r2 -match "(\d+)") {
                    $v2 = [int]$matches[1]
                    return @($v1, $v2)
                }
            }
        }
    }
    return @(0,0)
 }

 function Is_Display_BT2020 {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $colorspace = Search_video_info $Media_info "Color primaries"

    return ($colorspace -eq "BT.2020")
}

 function Get_Title {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    return Search_media_info $Media_info "General" "Movie name"

}

function Get_L1_MaxCLL {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file
    )
    $a = [string](& $global:dovi_tool info -s $rpu_file)
    if ($a -match ".* \(L1\): MaxCLL: (\d+)\.(\d+) nits, MaxFALL: (\d+)\.(\d+) nits") {
        $maxcll = [int]$matches[1]
        $ex1 = [int]$matches[2]
        $maxfall = [int]$matches[3]
        $ex2 = [int]$matches[4]
        if ($ex1 -ge 50) { $maxcll += 1 }
        if ($ex2 -ge 50) { $maxfall += 1 }
        return @($maxcll, $maxfall)
    }
    return @(0,0)
}

function Get_L1_Luminance {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file
    )
    $a = [string](& $global:dovi_tool info -s $rpu_file)
    if ($a -match ".* RPU Mastering display\: 0.(\d\d\d\d)/(\d+).*") {
        $l1 = [int]$matches[1]
        $l2 = [int]$matches[2]
        return @($l1, $l2)
    }
    return @(0,0)
}

function Get_l6_Luminance {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file
    )
    $a = [string](& $global:dovi_tool info -s $rpu_file)
    if ($a -match ".*L6 metadata\: Mastering display\: 0.(\d\d\d\d)/(\d+) nits.*") {
        $l1 = [int]$matches[1]
        $l2 = [int]$matches[2]
        return @($l1, $l2)
    }
    return @(0,0)
}

function Get_L6_MaxCLL {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file
    )
    $a = [string](& $global:dovi_tool info -s $rpu_file)
    if ($a -match ".*L6 metadata\: Mastering display\: .* MaxCLL\: (\d+) nits, MaxFALL\: (\d+) nits") {
        $maxcll = [int]$matches[1]
        $maxfall = [int]$matches[2]
        return @($maxcll, $maxfall)
    }
    return @(0,0)
}

function Get_Analysis_MaxCLL {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$analysis_file
    )
    $a = [string](Get-Content $analysis_file)
    if ($a -match ".*<Level6 level=\""6\"">.*<MaxCLL>(\d+)(\.\d+)?.*<MaxFALL>(\d+)(\.\d+)?.*") {
        $maxcll = [int]$matches[1]
        $maxfall = [int]$matches[3]
        return @($maxcll, $maxfall)
    }
    return @(0,0)
}

#
##########################################################################################################
# Functions that manipulate the files
##########################################################################################################
#
function Change_title {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$input_file,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$title
    )
    & $global:mkvpropedit "$input_file" --edit info --tags all: --delete title --add title="$title"
    return $LASTEXITCODE

}

function Test_mkv {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$input_file
    )
    $test = $global:tmp_dir + "Temp_*.mkv"
    $i = 0
    $did_lock = (Lock_disk $input_file)
    $file = gci $input_file
    $fname = $global:tmp_dir + "Temp_" + $file.BaseName + ".mkv"
    $arg= @("--priority", "lower", "--output", $fname, "--no-audio", "--no-subtitles", "--no-chapters", '(', $input_file, ')')
    #
    #[void] the function so all of the output doesn't get returned
    #
    try {
        [void](& $global:mkvmerge $arg)
        if ($LASTEXITCODE -ne 0) {
            $ret = $false;
        }
        else {
            $ret = $true
        }
    }
    catch {
        $ret = $false
    }
    finally{
        Remove-File $fname
        Unlock_disk $did_lock
    }
    return $ret
}


function Create_dovi_layer_from_hdr10 {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$hdr10_json,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file,
        [Parameter(Mandatory = $true, Position = 2)]
        [System.Object]$luminance,
        [Parameter(Mandatory = $true, Position = 3)]
        [System.Object]$maxcll
    )

    if (Test-Path $rpu_file -PathType Leaf) {
        return
    }
    Info "Create RPU from HDR10+ information"
    $l2 = $luminance[1]
    $l1 = $luminance[0]
    $m1 = $maxcll[0]
    $m2 = $maxcll[1]

    Info "Creating RPU with Maxcll of $m1,$m2 and Maxtering Display of $l1,$l2"
    $tmp = $rpu_file + ".h10todv.json"
    "{"                     | Out-File -Encoding Ascii "$tmp"
    """length"": 0,"        | Out-File -Encoding Ascii -Append "$tmp"
    """level2"": ["         | Out-File -Encoding Ascii -Append "$tmp"
    "{"                     | Out-File -Encoding Ascii -Append "$tmp"
    """target_nits"": 100"  | Out-File -Encoding Ascii -Append "$tmp"
    "},"                    | Out-File -Encoding Ascii -Append "$tmp"
    "{"                     | Out-File -Encoding Ascii -Append "$tmp"
    """target_nits"": 600"  | Out-File -Encoding Ascii -Append "$tmp"
    "},"                    | Out-File -Encoding Ascii -Append "$tmp"
    "{"                     | Out-File -Encoding Ascii -Append "$tmp"
    """target_nits"": 1000" | Out-File -Encoding Ascii -Append "$tmp"
    "},"                    | Out-File -Encoding Ascii -Append "$tmp"
    "{"                     | Out-File -Encoding Ascii -Append "$tmp"
    """target_nits"": 2000" | Out-File -Encoding Ascii -Append "$tmp"
    "}"                    | Out-File -Encoding Ascii -Append "$tmp"
    "],"                    | Out-File -Encoding Ascii -Append "$tmp"
    """level6"": {"         | Out-File -Encoding Ascii -Append "$tmp"
    """max_display_mastering_luminance"": $l2,"      | Out-File -Encoding Ascii -Append "$tmp"
    """min_display_mastering_luminance"": $l1,"      | Out-File -Encoding Ascii -Append "$tmp"
    """max_content_light_level"": $m1,"              | Out-File -Encoding Ascii -Append "$tmp"
    """max_frame_average_light_level"": $m2"         |  Out-File -Encoding Ascii -Append "$tmp"
    "}"                                              |  Out-File -Encoding Ascii -Append "$tmp"
    "}"                                              |  Out-File -Encoding Ascii -Append "$tmp"

    $tmp1 = $rpu_file + ".tmp.bin"
    $arg = @("generate", "-j", """$tmp""", "--hdr10plus-json", """$hdr10_json""", "--rpu-out", """$tmp1""")
    try {
        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $a = "dovi_tool generate failed with error code " + [string]($proc.ExitCode)
            FatalError $a
         }
    }
    catch {
        Remove-File $tmp1
        throw
    }
    # This is to catch when we control-c out of the program
    finally {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id
            Remove-File $tmp1
            throw
        }
    }

    Rename-Item $tmp1 $rpu_file

}

function Dovi_inject {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$bl_file,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$rpu_file,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$output_file
    )

    $tmp = $output_file + ".tmp.hevc"
    $arg = @("inject-rpu", "--rpu-in", """$rpu_file""", "--input", """$bl_file""", "--output", """$tmp""")
    try {

        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $a = "ERROR- dovi_tool inject-rpu failed with error code " + [string]($proc.ExitCode)
            FatalError $a
         }
    }
    catch {
        Remove-File $tmp
        throw
    }
    # This is to catch when we control-c out of the program
    finally {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id
            Remove-File $tmp
            throw
        }
    }
    Rename-Item $tmp $output_file
}

function Dovi_mux {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [switch]$do_full,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$bl_file,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$el_file,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$output_file
    )

    $tmp = $output_file + ".tmp.hevc"
    $arg = @()
    if ($do_full -eq $false) {
        $arg += @("-m", "2")
    }
    $arg += @("mux", "--bl", """$bl_file""", "--el", """$el_file""")
    if ($do_full -eq $false) {
        $arg += @("--discard")
    }
    $arg += @("--output", """$tmp""")
    try {

        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $a = "ERROR- dovi_tool mux failed with error code " + [string]($proc.ExitCode)
            FatalError $a
         }
    }
    catch {
        Remove-File $tmp
        throw
    }
    # This is to catch when we control-c out of the program
    finally {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id
            Remove-File $tmp
            throw
        }
    }
    Rename-Item $tmp $output_file
}

function Extract_hevc {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$track,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$input_file,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$output_file
    )
    if (Test-Path -Path $output_file -PathType Leaf) {
        return
    }

    Info "Demuxing video"

    $extr_name_tmp = $output_file + ".tmp.hevc"

    $strack = [string]$track

    $meta_name = $extr_name + ".meta"
    if (-not (Test-Path -Path $output_file -PathType Leaf)) {
        $did_lock = (Lock_disk $input_file)

        try {

            if (Is_Windows) {
                $proc = Start-Process -FilePath $global:mkvextract -ArgumentList @("""$input_file""", "tracks", "${strack}:""$extr_name_tmp""") -PassThru -windowstyle hidden
            }
            else {
                $proc = Start-Process -FilePath $global:mkvextract -ArgumentList @("""$input_file""", "tracks", "${strack}:""$extr_name_tmp""") -PassThru
            }

            Wait-Process -InputObject $proc
            if ($proc.ExitCode -ne 0) {
                $a = "ERROR- MKVExtract failed with error code " + [string]($proc.ExitCode)
                FatalError $a
            }
        }
        catch {
            Remove-File $extr_name_tmp
            Unlock_disk $did_lock
            throw
        }
        # This is to catch when we control-c out of the program
        finally {
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id
                Remove-File $extr_name_tmp
                Unlock_disk $did_lock
                throw
            }
        }

        Rename-Item $extr_name_tmp $output_file
        Unlock_disk $did_lock
    }
}

function Extract_dovi_layer {
    param (
        [Parameter(Mandatory=$true, Position = 0)]
        [switch]$is_rpu,
        [Parameter(Mandatory=$true, Position = 1)]
        [string]$input_hevc,
        [Parameter(Mandatory=$true, Position = 2)]
        [string]$el_file,
        [Parameter(Mandatory=$false)]
        [string]$bl_file="",
        [switch]$nom2=$false
       )

    if (-not (Test-Path $el_file -PathType Leaf)) {

        $bl_tmp = $el_file + ".bltmp.hevc"
        $el_tmp = $el_file + ".tmp.hevc"
        #
        # We use the input_hevc to extract RPU, because if the Dolby is MEL-only, extractuging
        # from the EL file doesn't work.
        #
        try {
            if ($is_rpu) {
                $arg = @()
                if ($nom2 -eq $false) {
                    $arg += @("-m", "2")
                }
                $arg += @("extract-rpu", "--rpu-out", """$el_tmp""", "--input", """$input_hevc""")
            }
            else {
                $arg = @("demux", "--bl-out", """$bl_tmp""", "--el-out", """$el_tmp""", "--input", """$input_hevc""")
            }

            if (Is_Windows) {
                $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru -windowstyle hidden
            }
            else {
                $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru
            }
            Wait-Process -InputObject $proc
            if ($proc.ExitCode -ne 0) {
                $a = "Dovi_tool failed to extract with error code " + [string]($proc.ExitCode)
                FatalError $a

            }
        }
        catch {
            Remove-File $el_tmp
            Remove-File $bl_tmp
            throw
        }
        # This is to catch when we control-c out of the program
        finally {
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id
                Remove-File $el_tmp
                Remove-File $bl_tmp
                throw
            }
        }
        if (Test-Path $bl_tmp -PathType Leaf) {
            if ($bl_file -ne "") {
                Rename-Item $bl_tmp $bl_file
            }
            else {
                Remove-Item $bl_tmp
            }
        }
        Rename-Item $el_tmp $el_file
    }
}


function Create_hdr10plus_json_file {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$input_file,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$output_file
    )

    if (Test-Path -Path $output_file -PathType Leaf) {
        return
    }
    Info "Create Hdr10+ json file"
    $jtmp = $output_file + ".tmp.json"

    $arg = @("extract", """$input_file""", "-o", """$jtmp""")
    try {
        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:hdr10plus_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:hdr10plus_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $a = "Hdr10plus_tool failed with error code " + [string]($proc.ExitCode)
            FatalError $a
        }
    }
    catch {
        Remove-File $jtmp
        throw
    }
    # This is to catch when we control-c out of the program
    finally {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id
            Remove-File $jtmp
            throw
        }
    }
    Rename-Item $jtmp $output_file
 }

 Function Create_chp_file {
    param (
     [Parameter(Mandatory = $true, Position = 0)]
     [string]$el_file,             # input .hevc file
     [Parameter(Mandatory = $true, Position = 1)]
     [string]$output_name          # output file name
    )

    $chp_file_tmp = $output_name + ".tmp"

    if (-not (Test-Path $output_name -PathType Leaf)) {
        $count = 0
        try {
            & $global:ffprobe -select_streams v -show_frames -show_entries frame=pict_type,key_frame -v quiet -of csv $el_file | ForEach-Object {
                if ( $_ -match "frame," ) {
                    if ( $_ -match "frame,1,I" ) {
                        echo "$count I -1"
                    }
                    if ( $_ -match "frame,0,I" ) {
                        echo "$count i -1"
                    }
                    elseif ($_ -match "frame,0.P" ) {
                        #echo "$count P -1"
                    }
                    $count += 1
                }
            } | Out-File -encoding ascii  $chp_file_tmp
        }
        catch {
            Remove-File $chp_file_tmp
            throw
        }
        # This is to catch when we control-c out of the program
        finally {
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id
                Remove-File $chp_file_tmp
                throw
            }
        }
        Rename-Item $chp_file_tmp $output_name
    }
}


function Extract_all_dovi_layers {
    param (
     [Parameter(Mandatory = $true, Position = 0)]
     [string]$extr_file,           # input .hevc file
     [Parameter(Mandatory = $true, Position = 1)]
     [string]$bl_file,             # output base layer
     [Parameter(Mandatory = $true, Position = 2)]
     [string]$el_file,             # output el_rpu file
     [Parameter(Mandatory = $true, Position = 3)]
     [string]$rpu_file,             # output rpu file (-m 2)
     [Parameter(Mandatory = $true, Position = 4)]
     [string]$rpufel_file          # output rpu file (not -m 2)
    )


    if ((-not (Test-Path $bl_file -PathType Leaf)) -or (-not (Test-Path $el_file -PathType Leaf))) {
        Info "Separating bl and el_rpu layers"
        Extract_dovi_layer $false $extr_file $el_file -bl_file $bl_file
    }
    if (-not (Test-Path $rpu_file -PathType Leaf)) {
        Info "Extracting RPU info"
        #
        # $bl_file was already created by the previous separate, so we don't want to overwrite it.
        #
        Extract_dovi_layer $true $extr_file $rpu_file
    }
    if (-not (Test-Path $rpufel_file -PathType Leaf)) {
        Info "Extracting RPU with FEL (if applicable) info "
        #
        # $bl_file was already created by the previous separate, so we don't want to overwrite it.
        #
        Extract_dovi_layer $true $extr_file $rpufel_file -nom2
    }
 }


function Parse_dv_info {
    param (
     [Parameter(Mandatory = $true, Position = 0)]
     [System.Object] $Media_info,
     [Parameter(Mandatory = $true, Position = 1)]
     [string]$rpufel_file,          # input rpu file (not -m2 )
     [Parameter(Mandatory = $true, Position = 2)]
     [string]$el_file,             # output el_rpu file
     [Parameter(Mandatory = $true, Position = 3)]
     [switch]$mel ,                # true if NOT baked encode
     [Parameter(Mandatory = $true, Position = 4)]
     [int]$dv,                      # dv_type from Dolby info
     [Parameter(Mandatory = $true, Position = 5)]
     [switch]$hybrid                # $true if hybrid in title
    )
    $array = @("","","", 0)
    if (7 -eq $dv) {
        $a = ( &$global:dovi_tool info -i $rpufel_file -f 60)
        $ts = ($a | Select-string -pattern ".*el_type""`: ""([MF])EL"".*")
        if ($ts -match ".*el_type""`: ""([MF])EL"".*") {
            $array[0] = $matches[1]
        }
        else {
            FatalError "Can't parse el_type from RPU"
        }
    }
    else {
        $array[0] = "M"
    }

    #
    # See if we have a FEL
    #

    $fsize = (Get-Item -Path $el_file).Length
    $duration = Get_video_duration $Media_info
    $brate = ($fsize * 8)/$duration
    #Write-Host "$fsize, $brate, $duration"
    $val = [string]([math]::Round(($brate/1MB),2))
    #
    # 2310000 = 2.2 Mbits
    #
    $r = [math]::round($brate / 1024.0 / 1024.0, 2)
    if ($brate -gt 2310000) {
        $r = [math]::round($brate / 1024.0 / 1024.0, 2)
        $array[2] = "Dolby type is FEL - bitrate is $r MB/sec"
        if (8 -eq $dv) {
            FatalError "Large bitrate type 8.1 ????"
        }
        if ($array[0] -ne "F") {
            Warning "Dolby type is flagged as MEL, even though bitrate is high"
        }
        if ($mel) {
            $array[1] = "_dvm"
            $array[3] = 8
        }
        else {
            $array[3] = 7
            $array[1] = "_dvmb"
        }
    }
    else {
        if ($array[0] -eq 'F') {
            Warning "Low Bitrate Dolby flaggs as FEL"
            $array[1] = "_dvmb"
            $array[2] = "Dolby type is Fel - bitrate is $r MB/sec"
            $array[3] = 7
        }
        else {
            $array[3] = 8
            if (8 -eq $dv) {
                if ($hybrid) {
                    $array[1] = "_dv8h"
                    $array[2] = "Dolby type is DV 8 (Hybrid)"
                }
                else {
                    $array[1] = "_dv806"
                    $array[2] = "Dolby type is DV 8.0.6"
                }
            }
            else {
                $array[2] = "Dolby type is MEL"
                $array[1] = "_dv8"
             }
        }
    }
    return $array
}



