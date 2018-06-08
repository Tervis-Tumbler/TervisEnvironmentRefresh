#Requires -Modules TervisEnvironment,TervisStorage
$ModulePath = (Get-Module -ListAvailable TervisEnvironmentRefresh).ModuleBase
. $ModulePath\RefreshDefinitions.ps1


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
        
        Invoke-Sql -dataSource $($Store.Computername) -database $($Store.Databasename) -sqlCommand "ALTER DATABASE [$($Store.Databasename)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;USE master;DROP DATABASE $($Store.Databasename);"
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
    
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Stop-Service SQLANYs_TervisDatabase}
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'D:\QcSoftware\Config','D:\QcSoftware\database.opts','D:\QcSoftware\profile.bat' 'C:\WCS Control' -Recurse -force}
    }
    foreach($target in $TargetDetails){
        Write-Verbose "Current Database - $($Target.DatabaseName)"
        $SanLocation = Get-EnvironmentRefreshLUNDetails -DatabaseName $($Target.Databasename)
        $SnapshottoAttach = $snapshots | where { $_.snapname -like "*$Computername*" -and $_.snapname -like "*$($target.DatabaseName)*"} | Sort-Object -Property CreationTime | Select -last 1

        if($RefreshType -eq "SQL"){
            Invoke-DetachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

        Write-Verbose "Setting Disk $($target.DiskNumber) Offline"
#        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -DriveLetter $($Target.DriveLetter) -State Offline
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Offline
        Write-Verbose "Dismounting $($target.SMPID)"
        Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        
        Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
        Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        Write-Verbose "Setting disk $($target.disknumber) online"
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Online

        Invoke-Command -ComputerName $Computername -ScriptBlock { do { sleep 1} until (Test-Path $using:target.driveletter) }

        if($RefreshType -eq "SQL"){
            Invoke-AttachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

    }
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'C:\WCS Control\config','C:\WCS Control\database.opts','C:\WCS Control\profile.bat' D:\QcSoftware -Recurse -force }
        Invoke-Command -ComputerName $Computername -ScriptBlock {Start-Service SQLANYs_TervisDatabase}
    }
}

function Invoke-DetachSQLDatabase {
    param(
        [Parameter(Mandatory)]$Computer,
        [Parameter(Mandatory)]$Database
    )
    Invoke-SQL -dataSource $Computer -database $Database -sqlCommand "ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE; EXEC sp_detach_db '$database', 'true';"
}

function Invoke-AttachSQLDatabase {
    param(
        [Parameter(Mandatory)]$Computer,
        [Parameter(Mandatory)]$Database
    )
    
    $SQLTarget = Get-EnvironmentRefreshTargetDetails -Hostname $Computer | where databasename -match $Database

    $SQLDBFiles = invoke-command -ComputerName $Computer -ScriptBlock {get-childitem -file -Path $($using:SQLTarget.driveletter) | where {$_.name -match "\..df$"}} 
    $SQLDBFileParameter = ($SQLDBFiles | % {"( FILENAME = N'$($SQLTarget.DriveLetter)\$_' )"}) -join ","
    Invoke-SQL -dataSource $Computer -database "master" -sqlCommand "CREATE DATABASE $($Database.toupper()) ON $SQLDBFileParameter FOR ATTACH"
}

function Set-EnvironmentRefreshDiskState{
    param(
        [Parameter(Mandatory)]$Computername,
        
        [Parameter(Mandatory)]$DiskNumber,

#        [Parameter(Mandatory)]$DriveLetter,

        [ValidateSet("Online","Offline")]
        [Parameter(Mandatory)]$State
    )
#    Get-Partition -CimSession $cimsession -DriveLetter ((Get-Volume -CimSession $cimsession -FileSystemLabel "DB_MES").DriveLetter | select disknumber    
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
        [ValidateSet(”DB_IMS”,“DB_MES”,"DB_ICMS","DB_Shipping","DB_Tervis_RMSHQ1","P-WCSDATA","ALL")]
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

function Get-OracleEnvironmentRefreshLUNDetails{
    param(
        [Parameter(Mandatory, ParameterSetName = "DetailsbyLUNNAME")]
        [String]$LUNName,
    
        [Parameter(Mandatory, ParameterSetName = "DetailsbyDBName")]
        [string]$DatabaseName,
    
        [Parameter(Mandatory, ParameterSetName = "ListOnly")]
        [switch]$List
    )
    
    If ($List){
        $OracleEnvironmentRefreshLUNDetails
    }
    elseif($LUNName){
        $OracleEnvironmentRefreshLUNDetails | Where LUNName -EQ $LUNName
    }
    else{
        $OracleEnvironmentRefreshLUNDetails | Where DatabaseName -EQ $DatabaseName
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

function Get-OracleEnvironmentRefreshTargetDetails{
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
        $OracleEnvironmentRefreshTargetDetails
    }
    Elseif ($Hostname){
        $OracleEnvironmentRefreshTargetDetails | where Computername -eq $Hostname
    }
    else{
        $OracleEnvironmentRefreshTargetDetails | Where {$_.Databasename -EQ $Databasename -and $_.Environmentname -eq $EnvironmentName}
    }
}


function Invoke-EnvironmentRefreshProcessForOracle {
    param(
        [Parameter(Mandatory)]$Computername
    )
    $TargetDetails = Get-OracleEnvironmentRefreshTargetDetails -Hostname $Computername
    Write-Verbose "Retrieving Snapshots"
    $snapshots = Get-SnapshotsFromVNX -TervisStorageArraySelection ALL
    
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Stop-Service SQLANYs_TervisDatabase}
    }
    foreach($target in $TargetDetails){
        Write-Verbose "Current Database - $($Target.DatabaseName)"
        $SanLocation = Get-EnvironmentRefreshLUNDetails -DatabaseName $($Target.Databasename)
        $SnapshottoAttach = $snapshots | where { $_.snapname -like "*$Computername*" -and $_.snapname -like "*$($target.DatabaseName)*"} | Sort-Object -Property CreationTime | Select -last 1

        if($RefreshType -eq "SQL"){
            Invoke-DetachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

        Write-Verbose "Setting Disk $($target.DiskNumber) Offline"
#        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -DriveLetter $($Target.DriveLetter) -State Offline
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Offline
        Write-Verbose "Dismounting $($target.SMPID)"
        Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        
        Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
        Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        Write-Verbose "Setting disk $($target.disknumber) online"
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Online

        Invoke-Command -ComputerName $Computername -ScriptBlock { do { sleep 1} until (Test-Path $using:target.driveletter) }

        if($RefreshType -eq "SQL"){
            Invoke-AttachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

    }
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'C:\WCS Control\config','C:\WCS Control\database.opts','C:\WCS Control\profile.bat' D:\QcSoftware -Recurse -force }
        Invoke-Command -ComputerName $Computername -ScriptBlock {Start-Service SQLANYs_TervisDatabase}
    }
}



function New-OracleEnvironmentRefreshSnapshot{
    param(
        [ValidateSet("PRD")]
        [String]$DatabaseName,

        [ValidateSet("Zeta",”Delta”,“Epsilon”,"ALL")]
        [String]$EnvironmentName
    )
    $Date = (get-date).tostring("yyyyMMdd-HH:mm:ss")
    #$DATE = (get-date).tostring("yyyyMMdd")
    if($EnvironmentName -eq "ALL"){
        $EnvironmentList = "Zeta","Delta","Epsilon"
    }
    else{$EnvironmentList = $EnvironmentName}
    $RefreshLUNDetails = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $Databasename
    $EnvironmentrefreshSnapshotDetails = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $Databasename
    $MasterSnapshotName = (Get-TervisRefreshSnapshotNamePrefix -DatabaseName PRD -MasterSnapshot) + $Date
    "New-VNXLUNSnapshot -LUNID $($EnvironmentrefreshSnapshotDetails.LUNID) -SnapshotName $MasterSnapshotName -TervisStorageArraySelection $($EnvironmentrefreshSnapshotDetails.SANLocation)"
    
    ForEach ($Environment in $EnvironmentList) {
        $EnvironmentPrefix = get-TervisEnvironmentPrefix -EnvironmentName $Environment
        $LUNID = $EnvironmentrefreshSnapshotDetails.LUNID
        $SnapshotName = (Get-TervisRefreshSnapshotNamePrefix -Database PRD -EnvironmentName $Environment) + $Date
        "Copy-VNXLUNSnapshot -SnapshotName $MasterSnapshotName -SnapshotCopyName $SnapshotName -TervisStorageArraySelection $($EnvironmentrefreshSnapshotDetails.SANLocation)"
    }
    
}

function Invoke-OracleEnvironmentRefreshProcess {
    param(
        [Parameter(Mandatory)]$Computername
    )
    $TargetDetails = Get-OracleEnvironmentRefreshTargetDetails -Hostname $Computername
    Write-Verbose "Retrieving Snapshots"
    $snapshots = Get-SnapshotsFromVNX -TervisStorageArraySelection ALL
    
    foreach($target in $TargetDetails){
        $SanLocation = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $($Target.Databasename)
        $SnapshottoAttach = $snapshots | where { $_.snapname -like "*$Computername*" -and $_.snapname -like "*$($target.DatabaseName)*"} | Sort-Object -Property CreationTime | Select -last 1

        if($RefreshType -eq "SQL"){
            Invoke-DetachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

        Write-Verbose "Setting Disk $($target.DiskNumber) Offline"
#        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -DriveLetter $($Target.DriveLetter) -State Offline
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Offline
        Write-Verbose "Dismounting $($target.SMPID)"
        Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        
        Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
        Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
        Write-Verbose "Setting disk $($target.disknumber) online"
        Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Online

        Invoke-Command -ComputerName $Computername -ScriptBlock { do { sleep 1} until (Test-Path $using:target.driveletter) }

        if($RefreshType -eq "SQL"){
            Invoke-AttachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName)            
        }

    }
    if($RefreshType -eq "Sybase"){
        Invoke-Command -ComputerName $Computername -ScriptBlock {Copy-Item 'C:\WCS Control\config','C:\WCS Control\database.opts','C:\WCS Control\profile.bat' D:\QcSoftware -Recurse -force }
        Invoke-Command -ComputerName $Computername -ScriptBlock {Start-Service SQLANYs_TervisDatabase}
    }
}

function Get-TervisRefreshSnapshotNamePrefix{
    [CmdletBinding()]
    param(
        [parameter(mandatory,ParameterSetName = "ByEnvironment")]
        [parameter(mandatory,ParameterSetName = "MasterSnapshot")]
        $DatabaseName,

        [parameter(mandatory,ParameterSetName = "ByEnvironment")]
        $EnvironmentName,

        [parameter(mandatory,ParameterSetName = "MasterSnapshot")]
        [switch]$MasterSnapshot
    )
    if($MasterSnapshot){
        $SnapshotName = ("DB-" + $DatabaseName + "_Master" + "_" ).toupper()
    }
    else{
        $EnvironmentPrefix = Get-TervisEnvironmentPrefix -EnvironmentName $EnvironmentName
        $SnapshotName = ("DB-" + $DatabaseName + "_" + $EnvironmentPrefix + "_").toupper()
    }
    $SnapshotName
}