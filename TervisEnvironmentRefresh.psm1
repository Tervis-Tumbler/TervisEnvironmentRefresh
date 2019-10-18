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
        if($target.Computername -eq "dlt-sql"){
            $Volume = Invoke-Command -ComputerName $target.Computername -ScriptBlock {Get-Volume -FileSystemLabel $using:Target.FilesystemLabel}
            $Partition = Invoke-Command -ComputerName $target.Computername -ScriptBlock {Get-Partition | Where-Object Driveletter -eq $using:Volume.DriveLetter}
            Write-Verbose "Setting Disk $($Partition.DiskNumber) - $($Volume.DriveLetter) - $($Volume.FileSystemLabel) Offline"
            Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($Partition.DiskNumber) -State Offline
            Write-Verbose "Dismounting $($target.SMPID)"
            Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
            
            Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
            Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
            Write-Verbose "Setting disk $($Partition.DiskNumber) online"
            Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($Partition.DiskNumber) -State Online
            Invoke-Command -ComputerName $Computername -ScriptBlock { 
                do { 
                    sleep 1
                    $Disk = Get-Disk -Number $using:Partition.DiskNumber
                    $Partition = Get-Partition -DiskNumber $Disk.Number | Where-Object OperationalStatus -eq "Online"
                } 
                until (($Disk.OperationalStatus -eq "Online" ) -and ($Partition.DriveLetter))
            }
            $VolumePostAttach = Invoke-Command -ComputerName $target.Computername -ScriptBlock {Get-Volume -FileSystemLabel $using:Target.FilesystemLabel}
    #        $PartitionPostAttach = Get-Partition | Where-Object Driveletter -eq $VolumePostAttach.DriveLetter
            Write-Verbose "Drive letter is now $($VolumePostAttach.DriveLetter)"
        }
#        Elseif($Target.Computername -eq "eps-sql"){
        Else{
            Write-Verbose "Setting Disk $($target.DiskNumber) Offline"
#            Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Offline
            Write-Verbose "Dismounting $($target.SMPID)"
            Dismount-VNXSnapshot -SMPID $($Target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
            
            Write-Verbose "Mounting $($SnapshottoAttach.SnapName)"
            Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $($target.SMPID) -TervisStorageArraySelection $($SANLocation.SANLocation)
            Write-Verbose "Setting disk $($target.disknumber) online"
            Set-EnvironmentRefreshDiskState -Computername $($target.Computername) -DiskNumber $($target.DiskNumber) -State Online
            Invoke-Command -ComputerName $Computername -ScriptBlock { do { sleep 1} until (Test-Path $using:target.driveletter) }
        }

        if($RefreshType -eq "SQL"){
            Invoke-AttachSQLDatabase -Computer $($Target.Computername) -Database $($Target.DatabaseName) -DriveLetter "$($Volume.DriveLetter):"
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
        [Parameter(Mandatory)]$Database,
        [Parameter(Mandatory)]$DriveLetter
    )
    
#    $SQLTarget = Get-EnvironmentRefreshTargetDetails -Hostname $Computer | where databasename -match $Database

    $SQLDBFiles = Invoke-Command -ComputerName $Computer -ScriptBlock {get-childitem -File -Path $using:DriveLetter | where Name -match "\..df$"} 
    $SQLDBFileParameter = ($SQLDBFiles | % {"( FILENAME = N'$($DriveLetter)\$_' )"}) -join ","
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

function New-OracleEnvironmentRefreshSnapshot{
    param(
        [ValidateSet("PRD")]
        [String]$DatabaseName,

        [ValidateSet("Zeta","Delta","Epsilon","ALL")]
        [String]$EnvironmentName
    )
    $Date = (get-date).tostring("yyyyMMdd-HH:mm:ss")
    #$DATE = (get-date).tostring("yyyyMMdd")
    if($EnvironmentName -eq "ALL"){
        $EnvironmentList = "Zeta","Delta","Epsilon"
    }
    else{$EnvironmentList = $EnvironmentName}
#    $RefreshLUNDetails = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $Databasename
    $EnvironmentrefreshSnapshotDetails = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $Databasename
    $MasterSnapshotName = (Get-TervisRefreshSnapshotNamePrefix -DatabaseName PRD -MasterSnapshot) + $Date

    $TimeSpan = New-TimeSpan -Minutes 5
    $Credential = Get-PasswordstatePassword -ID 4782 -AsCredential
    $SSHSession = New-SSHSession -ComputerName $EnvironmentrefreshSnapshotDetails.Computername -Credential $Credential -AcceptKey
    $SSHShellStream = New-SSHShellStream -SSHSession $SSHSession
#    $SSHShellStream.WriteLine("hostname")
#    $SSHShellStream.Read()
    $SSHShellStream.WriteLine("prd")
    $SSHShellStream.Expect("prd:PRD",$TimeSpan)
    #Invoke-SSHStreamExpectAction -ShellStream $SSHShellStream -ExpectString "prd:PRD" -TimeOut 300 -Command "/u01/app/oracle/DBA/scripts/snap_db_backup_mode.sh begin" -Action "sync" -Verbose
    $SSHShellStream.WriteLine("/u01/app/oracle/DBA/scripts/snap_db_backup_mode.sh begin")
    $SSHShellStream.Expect("prd:PRD",$TimeSpan)
#    $SSHShellStream.WriteLine("sync")
#    $SSHShellStream.Expect("prd:PRD",$TimeSpan)
    
    New-VNXLUNSnapshot -LUNID $($EnvironmentrefreshSnapshotDetails.LUNID) -SnapshotName $MasterSnapshotName -TervisStorageArraySelection $($EnvironmentrefreshSnapshotDetails.SANLocation)
    
    $SSHShellStream.WriteLine("/u01/app/oracle/DBA/scripts/snap_db_backup_mode.sh end")
    $SSHShellStream.Expect("prd:PRD",$TimeSpan)
    
    ForEach ($Environment in $EnvironmentList) {
#        $EnvironmentPrefix = get-TervisEnvironmentPrefix -EnvironmentName $Environment
#        $LUNID = $EnvironmentrefreshSnapshotDetails.LUNID
        $SnapshotName = (Get-TervisRefreshSnapshotNamePrefix -Database PRD -EnvironmentName $Environment) + $Date
        Copy-VNXLUNSnapshot -SnapshotName $MasterSnapshotName -SnapshotCopyName $SnapshotName -TervisStorageArraySelection $($EnvironmentrefreshSnapshotDetails.SANLocation)
    }
    Remove-SSHSession $SshSession    
}

function Invoke-OracleEnvironmentRefreshProcess {
    param(
        [Parameter(Mandatory)]$Computername
    )
    $Credential = Find-PasswordstatePassword -HostName ($Computername + ".tervis.prv") -UserName "Root" -AsCredential
    $SSHSession = New-SSHSession -ComputerName $Computername -Credential $Credential -AcceptKey
    $TargetDetails = Get-OracleEnvironmentRefreshTargetDetails -Hostname $Computername
    Write-Verbose "Retrieving Snapshots"
    $snapshots = Get-SnapshotsFromVNX -TervisStorageArraySelection VNX5200

    $SSHCommand = "umount /ebsdata; umount /ebsdata2"
    Invoke-SSHCommand -SSHSession $SSHSession -Command $SSHCommand

    foreach($target in $TargetDetails){
        $LUNDetails = Get-OracleEnvironmentRefreshLUNDetails -DatabaseName $($Target.Databasename)
        $SnapshotNamePrefix = Get-TervisRefreshSnapshotNamePrefix -DatabaseName $Target.DatabaseName -EnvironmentName $Target.Environmentname
        $SnapshottoAttach = $snapshots | where { $_.snapname -match $SnapshotNamePrefix} | Sort-Object -Property CreationTime | Select -last 1

        Write-Verbose "Dismounting snapshot for $($Target.Databasename) on $($Target.ComputerName) - SMP $($target.SMPID)"
        foreach($SMP in $target.SMPID){
            Dismount-VNXSnapshot -SMPID $SMP -TervisStorageArraySelection $($LUNDetails.SANLocation)
            Mount-VNXSnapshot -SnapshotName $($SnapshottoAttach.SnapName) -SMPID $SMP -TervisStorageArraySelection $($LUNDetails.SANLocation)
        }
        
    }
    Invoke-SSHCommand -SSHSession $SSHSession -command "iscsiadm -m node --refresh"
    sleep 2
    Invoke-SSHCommand -SSHSession $SSHSession -command "systemctl reload multipathd"
    Invoke-SSHCommand -SSHSession $SSHSession -command "vgscan"
    Invoke-SSHCommand -SSHSession $SSHSession -command "vgchange -ay"
    Invoke-SSHCommand -SSHSession $SSHSession -command "mount -a"
    get-sshsession | Remove-SSHSession
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


function Stop-OracleApplicationTier{
    [CmdletBinding()]
    param(
        [parameter(mandatory)][ValidateSet("zet-ias01")]$Computername
    )
    $ShutdownScriptPath = "/patches/cloning/scripts/shutdown_appstier.sh SBX"
    $ExpectString = '[applmgr@zet-ias01 ~]$'
    $Credential = Find-PasswordstatePassword -HostName ($Computername + ".tervis.prv") -UserName "applmgr" -AsCredential
    $SSHSession = New-SSHSession -HostName $Computername -Credential $Credential -AcceptKey
    $TimeSpan = New-TimeSpan -Minutes 5
    $SSHShellStream = New-SSHShellStream -SSHSession $SshSession
    $SSHShellStream.read() | Out-Null
#    $SSHShellStream.WriteLine($ShutdownScriptPath)
    $SSHShellStream.WriteLine("/patches/cloning/scripts/shutdown_appstier.sh SBX")
    if (-not $SSHShellStream.Expect($ExpectString,$TimeSpan)){
        Write-Error -Message "Command Timed Out" -Category LimitsExceeded -ErrorAction Stop
    }    
    $DebugOutput = $SSHShellStream.Read()
    Write-Debug $DebugOutput
    Get-SSHSession | Remove-SSHSession
}

function Stop-OracleDatabaseTier{
    [CmdletBinding()]
    param(
        [parameter(mandatory)][ValidateSet("zet-odbee01")]$Computername
    )
    $ShutdownScriptPath = "/patches/cloning/scripts/shutdown_dbtier.sh SBX"
    $ExpectString = '[oracle@zet-odbee01 ~]$'
    $Credential = Find-PasswordstatePassword -HostName ($Computername + ".tervis.prv") -UserName "Oracle" -AsCredential
    $SSHSession = New-SSHSession -HostName $Computername -Credential $Credential
    $TimeSpan = New-TimeSpan -Minutes 5
    $SSHShellStream = New-SSHShellStream -SSHSession $SshSession
    $SSHShellStream.read() | Out-Null
    $SSHShellStream.WriteLine($ShutdownScriptPath)
    
    if (-not $SSHShellStream.Expect($ExpectString,$TimeSpan)){
        Write-Error -Message "Command Timed Out" -Category LimitsExceeded -ErrorAction Stop
    }    
    $DebugOutput = $SSHShellStream.Read()
    Write-Debug $DebugOutput
    Get-SSHSession | Remove-SSHSession
}

function Invoke-ScheduledZetaOracleRefresh{
    try{
        $ComputerList = Get-OracleServerDefinition -Environment Zeta
        $ApplmgrUserCredential = Get-PasswordstatePassword -ID 4767 -AsCredential
        $OracleUserCredential = Get-PasswordstatePassword -ID 5571 -AsCredential
        $SystemsUsingOracleUserCredential = $ComputerList | Where-Object ServiceUserAccount -eq "oracle"
        $SystemsUsingApplmgrUserCredential = $ComputerList | Where-Object ServiceUserAccount -eq "applmgr"
        New-SSHSession -ComputerName $SystemsUsingOracleUserCredential.Computername -AcceptKey -Credential $OracleUserCredential
        New-SSHSession -ComputerName $SystemsUsingApplmgrUserCredential.Computername -AcceptKey -Credential $ApplmgrUserCredential
        $EBSIAS = Get-OracleServerDefinition -SID DEV | Where-Object Services -Match "EBSIAS"
        $EBSODBEE = Get-OracleServerDefinition -SID DEV | Where-Object Services -Match "EBSODBEE"
        Stop-OracleIAS -Computername $EBSIAS.ComputerName -SID SBX -SSHSession (get-sshsession -ComputerName $EBSIAS.Computername)
        Stop-OracleDatabase -Computername $OBIEEODBEE.Computername -SID SBX -SSHSession (get-sshsession -ComputerName $OBIEEODBEE.Computername)
        New-OracleEnvironmentRefreshSnapshot -DatabaseName PRD -EnvironmentName Zeta
        Invoke-OracleEnvironmentRefreshProcess -Computername "zet-odbee01"
    }
    catch{
        get-sshsession | remove-sshsession | Out-Null
        $Body = @"
        <html><body>
        <h2>$($_.InvocationInfo.MyCommand.Name)</h2>
            <p>$($_.exception.message)</p>
    
            <p>$($_.InvocationInfo.PositionMessage)</p>

        </body></html>
"@
        $FromAddress = "Mailerdaemon@tervis.com"
        $ToAddress = "dmohlmaster@tervis.com"
        $Subject = "***ACTION REQUIRED*** Zeta Scheduled Refresh Failed - $($_.InvocationInfo.MyCommand.Name)"
        Send-TervisMailMessage -From $FromAddress -To $ToAddress -Subject $Subject -Body $Body -BodyAsHTML
    }
}

function Install-OracleZetaScheduledEnvironmentRefreshPowershellApplication {
	param (
		$ComputerName
	)
    $ScheduledTaskCredential = New-Object System.Management.Automation.PSCredential (Get-PasswordstatePassword -AsCredential -ID 259)
    Install-PowerShellApplication -ComputerName $ComputerName `
        -EnvironmentName "Infrastructure" `
        -ModuleName "TervisEnvironmentRefresh" `
        -TervisModuleDependencies PasswordstatePowershell,TervisMicrosoft.PowerShell.Utility,TervisMailMessage,microsoft.powershell.Management,PasswordstatePowershell,TervisEnvironment,TervisEnvironmentRefresh,tervismicrosoft.powershell.Utility,TervisStorage `
        -PowerShellGalleryDependencies "Posh-SSH" `
        -ScheduledTasksCredential $ScheduledTaskCredential `
        -ScheduledTaskName "OracleZetaScheduledEnvironmentRefresh" `
        -RepetitionIntervalName "OnceAWeekFridayMorning" `
        -CommandString @"
    Invoke-ScheduledZetaOracleRefresh
"@
}