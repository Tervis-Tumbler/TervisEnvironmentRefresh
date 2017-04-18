#Requires -Modules TervisEnvironment,TervisStorage

function Invoke-EnvironmentRefreshProcessForStores {
    param(
        [ValidateSet(”Delta”,“Epsilon”,"ALL")]
        [String]$EnvironmentName
    )
    if($EnvironmentName -eq "ALL"){
        $EnvironmentList = Get-EnvironmentRefreshStoreDetails -List
    }
    else{$EnvironmentList = $EnvironmentName}
    $StoreDetails = Get-EnvironmentRefreshStoreDetails -Environment $EnvironmentName

    $StoresRestoreScript = "//fs1/disasterrecovery/Source Controlled Items/Refresh Scripts/StoresRestore.ps1"
    foreach($Store in $StoreDetails){
        $sqlquery = "ALTER DATABASE [$Store.Databasename] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; GO; USE master; GO; DROP DATABASE $($Store.Databasename); GO;"
        Invoke-Sqlcmd -ServerInstance $($Store.Computername) -Query $sqlquery
    }
    #Invoke-Command -ComputerName inf-dpm2016hq1 -FilePath $StoresRestoreScript
}

function Invoke-EnvironmentRefreshProcess {
    param(
        [ValidateSet("SQL","Sybase")]
        [Parameter(Mandatory)]$RefreshType,
        
        [Parameter(Mandatory)]$Computername
    )
    $TargetDetails = Get-EnvironmentRefreshTargetDetails -Hostname $Computername
    Write-Verbose "Retrieving Snapshots"
    $snapshots = Get-SnapshotsFromVNX -TervisStorageArraySelection ALL
    
    if($RefreshType -eq "SQL"){
        Write-Verbose "Stopping SQL Service"
        Invoke-Command -ComputerName $Computername -ScriptBlock {Stop-Service mssqlserver -force}
    }
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Stop-Service SQLANYs_TervisDatabase}
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'D:\QcSoftware\Config','D:\QcSoftware\database.opts','D:\QcSoftware\profile.bat' 'C:\WCS Control' -Recurse -force}
    }
    foreach($target in $TargetDetails){
        $SanLocation = Get-EnvironmentRefreshLUNDetails -DatabaseName $($Target.Databasename)
        $SnapshottoAttach = $snapshots | where { $_.snapname -like "*$Computername*" -and $_.snapname -like "*$($target.DatabaseName)*"} | select -last 1

        Write-Verbose "Setting Disk $($target.DiskNumber) Offline"
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -DriveLetter $($Target.DriveLetter) -State Offline
        Write-Verbose "Dismounting $($target.SMPID)"
        Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        
        Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
        Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        Write-Verbose "Setting disk $($target.disknumber) online"
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -DriveLetter $($Target.DriveLetter) -State Online
        write-host "Breakpoint"
    }
    if($RefreshType -eq "SQL"){
        Write-Verbose "Starting SQL service"
        Invoke-Command -ComputerName $Computername -ScriptBlock {Start-Service mssqlserver}
        Write-Verbose "Starting SQL Agent"
        Invoke-Command -ComputerName $Computername -ScriptBlock {start-service sqlserveragent}
        
    }
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'C:\WCS Control\config','C:\WCS Control\database.opts','C:\WCS Control\profile.bat' D:\QcSoftware -Recurse -force }
        Invoke-Command -ComputerName $Computername -ScriptBlock {Start-Service SQLANYs_TervisDatabase}
    }
}

function Set-EnvironmentRefreshDiskState{
    param(
        [Parameter(Mandatory)]$Computername,
        
        [Parameter(Mandatory)]$DiskNumber,

        [Parameter(Mandatory)]$DriveLetter,

        [ValidateSet("Online","Offline")]
        [Parameter(Mandatory)]$State
    )
    
#    $Session = New-PSSession -ComputerName $Computername
    if($state -eq "online"){
        $DiskOfflineCommandFile = @"
select disk $($DiskNumber)
$($State) disk
"@
    }
    if($State -eq "offline"){
        $DiskOfflineCommandFile = @"
select disk $($DiskNumber)
$($State) disk
"@
    }
    Invoke-Command -ComputerName $Computername -ScriptBlock {param($DiskOfflineCommandFile)
        $TempCommandfileLocation = [system.io.path]::GetTempFileName()
        $DiskOfflineCommandFile | Out-File -FilePath $TempCommandfileLocation -Encoding ascii
        & diskpart.exe /s $TempCommandfileLocation
        Remove-Item $TempCommandfileLocation -Force
    } -Args $DiskOfflineCommandFile
    
#    Disconnect-PSSession $session

}


function New-EnvironmentRefreshSnapshot{
    param(
        [ValidateSet(”DB_IMS”,“DB_MES”,"DB_ICMS","DB_Shipping","DB_RMSHQ_2017","P-WCSDATA","ALL")]
        [String]$LUNName,

        [ValidateSet(”Delta”,“Epsilon”,"ALL")]
        [String]$EnvironmentName
    )
    $DATE = (get-date).tostring("yyyyMMdd")
    if($LUNName -eq "ALL"){
        $LUNList = $EnvironmentRefreshLUNDetails.LUNName
    }
    else{$LUNList = $LUNName}
    if($EnvironmentName -eq "ALL"){
        $EnvironmentList = "Delta","Epsilon"
    }
    else{$EnvironmentList = $EnvironmentName}
    ForEach ($LUN in $LUNList){
        ForEach ($Environment in $EnvironmentList) {
            $EnvironmentPrefix = get-TervisEnvironmentPrefix -EnvironmentName $Environment
            $EnvironmentrefreshSnapshotDetails = Get-EnvironmentRefreshLUNDetails -LUNName $LUN
            $SourceComputer = $EnvironmentrefreshSnapshotDetails.Computername
            $LUNID = $EnvironmentrefreshSnapshotDetails.LUNID
            $SnapshotName = "$($LUN)_$EnvironmentPrefix-$($SourceComputer)_$DATE"
            New-VNXLUNSnapshot -LUNID $LUNID -SnapshotName $SnapshotName -TervisStorageArraySelection $EnvironmentrefreshSnapshotDetails.SANLocation
        }
    }
}

function Get-EnvironmentRefreshStoreDetails{
    param(
        [Parameter(Mandatory, ParameterSetName = "DetailsbyBO")]
        [String]$Computername,
    
        [Parameter(Mandatory, ParameterSetName = "DetailsbyDatabase")]
        [string]$DatabaseName,

        [Parameter(Mandatory, ParameterSetName = "DetailsbyEnvironment")]
        [ValidateSet(”Delta”,“Epsilon”)]
        [string]$Environment,
    
        [Parameter(Mandatory, ParameterSetName = "ListOnly")]
        [switch]$List
    )
    
    If ($List){
        $EnvironmentRefreshStoreDetails
    }
    elseif($Computername){
        $EnvironmentRefreshStoreDetails | Where Computername -EQ $Computername
    }
    elseif($Environment){
        $EnvironmentRefreshStoreDetails | Where Environment -EQ $Environment
    }
    else{
        $EnvironmentRefreshStoreDetails | Where DatabaseName -EQ $DatabaseName
    }
}

function Get-EnvironmentRefreshLUNDetails{
    param(
        [Parameter(Mandatory, ParameterSetName = "DetailsbyLUNNAME")]
        [String]$LUNName,
    
        [Parameter(Mandatory, ParameterSetName = "DetailsbyDBName")]
        [string]$DatabaseName,
    
        [Parameter(Mandatory, ParameterSetName = "ListOnly")]
        [switch]$List
    )
    
    If ($List){
        $EnvironmentRefreshLUNDetails
    }
    elseif($LUNName){
        $EnvironmentRefreshLUNDetails | Where LUNName -EQ $LUNName
    }
    else{
        $EnvironmentRefreshLUNDetails | Where DatabaseName -EQ $DatabaseName
    }
}

function Get-EnvironmentRefreshTargetDetails{
    param(
        [Parameter(mandatory, ParameterSetName = "DetailsbyDBName")]
        $Databasename,

        [Parameter(mandatory, ParameterSetName = "DetailsbyDBName")]
        [ValidateSet(”Delta”,“Epsilon”)]
        $EnvironmentName,

        [Parameter(mandatory, ParameterSetName = "DetailsbyHostname")]
        $Hostname,

        [Parameter(Mandatory, ParameterSetName = "ListOnly")]
        [switch]$List
    )
    If ($List){
        $EnvironmentRefreshTargetDetails
    }
    Elseif ($Hostname){
        $EnvironmentRefreshTargetDetails | where Computername -eq $Hostname
    }
    else{
        $EnvironmentRefreshTargetDetails | Where {$_.Databasename -EQ $Databasename -and $_.Environmentname -eq $EnvironmentName}
    }
}

$EnvironmentRefreshLUNDetails = [pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1005"
    LUNName = "DB_IMS"
    Databasename = "IMS"
    RefreshType = "DB"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1004"
    LUNName = "DB_MES"
    Databasename = "MES"
    RefreshType = "DB"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1769"
    LUNName = "DB_ICMS"
    Databasename = "ICMS"
    RefreshType = "DB"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1001"
    LUNName = "DB_Shipping"
    Databasename = "Shipping"
    RefreshType = "DB"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "SQL"
    LUNID = "1011"
    LUNName = "DB_TervisRMSHQ1"
    Databasename = "Tervis_RMSHQ1"
    RefreshType = "DB"
    SANLocation = "VNX5300"
},
[pscustomobject][ordered]@{
    Computername = "P-WCS"
    LUNID = "1745"
    LUNName = "P-WCSDATA"
    Databasename = "Tervis"
    RefreshType = "Disk"
    SANLocation = "VNX5300"
}

$EnvironmentRefreshTargetDetails = [pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "MES"
    VolumeName = "DB_MES"
    RefreshType = "DB"
    DiskNumber = "4"
    SMPID = "3960"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "IMS"
    VolumeName = "DB_IMS"
    RefreshType = "DB"
    DiskNumber = "3"
    SMPID = "3961"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "ICMS"
    VolumeName = "DB_ICMS"
    RefreshType = "DB"
    DiskNumber = "10"
    SMPID = "3913"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "Shipping"
    VolumeName = "DB_Shipping"
    RefreshType = "DB"
    DiskNumber = "7"
    SMPID = "3954"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "Tervis_RMSHQ1"
    VolumeName = "Tervis_RMSHQ1"
    RefreshType = "DB"
    DiskNumber = "6"
    SMPID = "63836"
},
[pscustomobject][ordered]@{
    Computername = "DLT-WCSSybase"
    EnvironmentName = "Delta"
    DatabaseName = "Tervis"
    VolumeName = "Data"
    RefreshType = "Disk"
    DiskNumber = "3"
    SMPID = "3957"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "MES"
    VolumeName = "DB_MES"
    RefreshType = "DB"
    DiskNumber = "4"
    DriveLetter = "I"
    VolumeNumber = "7"
    SMPID = "3997"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "IMS"
    VolumeName = "DB_IMS"
    RefreshType = "DB"
    DiskNumber = "5"
    DriveLetter = "P"
    VolumeNumber = "8"
    SMPID = "3996"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "ICMS"
    VolumeName = "DB_ICMS"
    RefreshType = "DB"
    DiskNumber = "10"
    DriveLetter = "K"
    VolumeNumber = "12"
    SMPID = "3912"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "Shipping"
    VolumeName = "DB_Shipping"
    RefreshType = "DB"
    DiskNumber = "8"
    DriveLetter = "J"
    VolumeNumber = "11"
    SMPID = "3977"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "Tervis_RMSHQ1"
    VolumeName = "DB_Tervis_RMSHQ1_VNX5300"
    RefreshType = "DB"
    DiskNumber = "13"
    DriveLetter = "F"
    VolumeNumber = "13"
    SMPID = "4068"
},
[pscustomobject][ordered]@{
    Computername = "EPS-WCSSybase"
    EnvironmentName = "Epsilon"
    DatabaseName = "Tervis"
    VolumeName = "Data"
    RefreshType = "Disk"
    DiskNumber = "3"
    DriveLetter = "D"
    SMPID = "4000"
}


$EnvironmentRefreshStoreDetails = [pscustomobject][ordered]@{
    Computername = "dlt-rmsbo1"
    Databasename = "ospreystoredb"
    Environment = "Delta"
},
[pscustomobject][ordered]@{
    Computername = "dlt-rmsbo2"
    Databasename = "Orangebeachdb"
    Environment = "Delta"
},
[pscustomobject][ordered]@{
    Computername = "dlt-rmsbo3"
    Databasename = "Charleston"
    Environment = "Delta"
},
[pscustomobject][ordered]@{
    Computername = "eps-rmsbo1"
    Databasename = "ospreystoredb"
    Environment = "Epsilon"
},
[pscustomobject][ordered]@{
    Computername = "eps-rmsbo2"
    Databasename = "Orangebeachdb"
    Environment = "Epsilon"
},
[pscustomobject][ordered]@{
    Computername = "eps-rmsbo3"
    Databasename = "Charleston"
    Environment = "Epsilon"
}