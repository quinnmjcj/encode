
Import-Module MediaOS

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
                Write-Error "Unexpected line ($line)"
                Exit(1)
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
                $values.Add($matches[1].Trim(), $matches[2].Trim())
            }
            else {
                Write-Error "Unexpected line for key $key ($line)"
                Exit(1)
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
    $use = $global:mediaInfo + " """ + $Filename + """ 2>&1"
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
        [string] $Output_name,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Ext_extra,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Ext_extra_dv
    )
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
    $hash.add("extr_file", $dir + $Output_name + ".extr.hevc")
    $hash.Add("bl_file", $dir + $Output_name + ".bl.hevc")
    $hash.add("el_rpu_file", $dir + $Output_name + ".el_rpu.hevc")
    $hash.add("chapter_file", $dir + $Output_name + ".chp")
     $hash.add("tmp1_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp1.mkv")
    $hash.add("tmp2_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp1_t00.mkv")
    $hash.add("tmp3_mkv", $dir + $Output_name + "." + $Ext_extra + ".tmp3.mkv")
    $hash.add("enc_file", $dir + $Output_name + "." + $Ext_extra + ".enc.hevc")
    #
    # Files that depend on DV information
    #
    $hash.add("dv_file", $dir + $output_name + "." + $Ext_extra_dv + ".dv1.hevc")
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
    if ( $v -match " (\d\d\d) pixels") {
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
    if ( $v -match " (\d\d\d) pixels") {
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
        Write-Host -ForegroundColor red "ERROR: Can't determine interlacing field order: $j ++++"
        Exit(1)
    }
    return ""
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
            if ( $cs.NumberOfLogicalProcessors -gt 8 ) {
                return @("--pools", "8", "--frame-threads", "3", "--wpp")
            }
        }
        else {
            return @("--wpp")
        }
    }
    elseif (Threads -eq "default") {
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
        [string]$No_bt709  
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

        $luminance = Get_luminance_string $Media_info
        if ($luminance -eq "") {
            Write-Host -ForegroundColor red "WARNING: --luminance is missing ++++"
        }

        $display = Get_Display_colors  $Media_info
        if ($display -eq "") {
            Write-Host -ForegroundColor red "WARNING: Display is not P3 or BT2020 or spelled out ++++"
        }

        if (($luminance -ne "") -and ($display -ne "")) {
            $res += @("--transfer", "smpte2084", "--hdr10", "--hdr10-opt")
            $res += @("--master-display", """${display}L(${luminance})""")
        }
        else {
            $res += @("--transfer", "bt2020-10")
        }

        $maxcll = Maxcll_String $Media_info

        if ($maxcll.length -ne 0) {
            $res += @("--max-cll", $maxcll)
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
        Write-Host -ForegroundColor red "ERROR: Can't get frame rate ++++"
        Exit(1)
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


 function Get_luminance_string {
    param (  
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object] $Media_info
    )
    $r = Search_video_info $Media_info "Mastering display luminance"
    if ($r -match "min\: 0\.(\d\d\d\d) cd\/m2, max\: (\d+) cd\/m2") {
        $first = [int]$matches[1]
        $second = [int]$matches[2]
        return [string]$second + "0000" + "," + [string]$first
    }
    return ""
 }

  function Maxcll_String {
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
                return [string]$v1 + "," + [string]$v2
            }
        }
    }
    return ""
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
        if (Test-Path -Path $fname -PathType Leaf) {
            Remove-Item $fname
        }
    }
    return $ret
}

function Dovi_inject {
    param ( 
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$bl_file,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$el_file,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$output_file
    )

    $tmp = $output_file + ".tmp.hevc"
    $arg = @("inject-rpu", "--rpu-in", """$el_file""", "--input", """$bl_file""", "--output", """$tmp""")
    try {

        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:dovi_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $tmp = "ERROR- dovi_tool inject-rpu failed with error code " + [string]($proc.ExitCode) + " ++++"
            Write-Host -ForegroundColor Red $tmp
            Exit(1)
         }
    }
    finally {
        if (-not $proc.HasExited) {          
            Stop-Process -Id $proc.Id
            Remove-Item $tmp
            Exit(2)
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
            $tmp = "ERROR- dovi_tool mux failed with error code " + [string]($proc.ExitCode) + " ++++"
            Write-Host -ForegroundColor Red $tmp
            Exit(1)
         }
    }
    finally {
        if (-not $proc.HasExited) {          
            Stop-Process -Id $proc.Id
            Remove-Item $tmp
            Exit(2)
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
   
    $extr_name_tmp = $output_file + ".tmp.hevc"

    $strack = [string]$track

    $meta_name = $extr_name + ".meta"
    if (-not (Test-Path -Path $output_file -PathType Leaf)) {

        try {

            if (Is_Windows) {
                $proc = Start-Process -FilePath $global:mkvextract -ArgumentList @("""$input_file""", "tracks", "${strack}:""$extr_name_tmp""") -PassThru -windowstyle hidden
            }
            else {
                $proc = Start-Process -FilePath $global:mkvextract -ArgumentList @("""$input_file""", "tracks", "${strack}:""$extr_name_tmp""") -PassThru
            }

            Wait-Process -InputObject $proc
            if ($proc.ExitCode -ne 0) {
                $tmp = "ERROR- MKVExtract failed with error code " + [string]($proc.ExitCode) + " ++++"
                Write-Host -ForegroundColor Red $tmp
                Exit(1)
            }
        }
        finally {
            if (-not $proc.HasExited) {          
                Stop-Process -Id $proc.Id
                Exit(2)
            }
        }
        #
        # Output file is $extr_name
        #
        #Remove-Item "$meta_name"
        Rename-Item $extr_name_tmp $output_file
    }
}

function Extract_dovi_layer {
    param (
        [Parameter(Mandatory=$true, Position = 0)]
        [switch]$is_rpu,
        [Parameter(Mandatory=$true, Position = 1)]
        [string]$input_hevc,
        [Parameter(Mandatory=$true, Position = 3)]
        [string]$el_file    
       )

    if (-not (Test-Path $el_file -PathType Leaf)) {    

        $bl_tmp = $el_file + ".bltmp.hevc"
        $el_tmp = $el_file + ".tmp.hevc"
             
        if ($is_rpu) {
            $arg = @("-m", "2", "extract-rpu", "--rpu-out", """$el_tmp""", "--input", """$input_hevc""")
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
            $tmp = "Dovi_tool failed with error code " + [string]($proc.ExitCode)
            Write-Host -ForegroundColor red $tmp
            Exit(1)
        }
        if (Test-Path $bl_tmp -PathType Leaf) {
            Remove-Item $bl_tmp
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


    if ( -not (Test-Path -Path $output_file -PathType Leaf) ) {

        $jtmp = $output_file + ".tmp.json"

        $arg = @("extract", """$input_file""", "-o", """$jtmp""")

        if (Is_Windows) {
            $proc = Start-Process -FilePath $global:hdr10plus_tool -ArgumentList $arg -PassThru -windowstyle hidden
        }
        else {
            $proc = Start-Process -FilePath $global:hdr10plus_tool -ArgumentList $arg -PassThru
        }
        Wait-Process -InputObject $proc
        if ($proc.ExitCode -ne 0) {
            $tmp = "Hdr10plus_tool failed with error code " + [string]($proc.ExitCode)
            Write-Host -ForegroundColor red $tmp
            Exit(1)
        }
        Rename-Item $jtmp $output_file
    }
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
        Rename-Item $chp_file_tmp $output_name
    }
}