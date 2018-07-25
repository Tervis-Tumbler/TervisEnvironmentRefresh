
$OracleEnvironmentRefreshLUNDetails = [pscustomobject][ordered]@{
    Computername = "EBSDB-PRD"
    LUNID = "PRD_CG"
    LUNName = "PRD_CG"
    Databasename = "PRD"
    RefreshType = "ODBEE"
    SANLocation = "VNX5200"
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
    LUNID = "4"
    LUNName = "DB_Tervis_RMSHQ1"
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
    DriveLetter = "G:"
    DiskNumber = "3"
    SMPID = "3960"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "IMS"
    VolumeName = "DB_IMS"
    RefreshType = "DB"
    DriveLetter = "F:"
    DiskNumber = "2"
    SMPID = "3961"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "ICMS"
    VolumeName = "DB_ICMS"
    RefreshType = "DB"
    DriveLetter = "K:"
    DiskNumber = "8"
    SMPID = "3913"
},
[pscustomobject][ordered]@{
    Computername = "DLT-SQL"
    EnvironmentName = "Delta"
    DatabaseName = "Tervis_RMSHQ1"
    VolumeName = "Tervis_RMSHQ1"
    RefreshType = "DB"
    DriveLetter = "L:"
    DiskNumber = "11"
    SMPID = "3998"
},
[pscustomobject][ordered]@{
    Computername = "DLT-WCSSybase"
    EnvironmentName = "Delta"
    DatabaseName = "Tervis"
    VolumeName = "Data"
    RefreshType = "Disk"
    DriveLetter = "D:"
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
    DriveLetter = "I:"
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
    DriveLetter = "P:"
    VolumeNumber = "8"
    SMPID = "3996"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "ICMS"
    VolumeName = "DB_ICMS"
    RefreshType = "DB"
    DiskNumber = "9"
    DriveLetter = "K:"
    VolumeNumber = "12"
    SMPID = "3912"
},
[pscustomobject][ordered]@{
    Computername = "EPS-SQL"
    EnvironmentName = "Epsilon"
    DatabaseName = "Tervis_RMSHQ1"
    VolumeName = "DB_Tervis_RMSHQ1_VNX5300"
    RefreshType = "DB"
    DiskNumber = "12"
    DriveLetter = "E:"
    VolumeNumber = "13"
    SMPID = "3999"
},
[pscustomobject][ordered]@{
    Computername = "EPS-WCSSybase"
    EnvironmentName = "Epsilon"
    DatabaseName = "Tervis"
    VolumeName = "Data"
    RefreshType = "Disk"
    DiskNumber = "3"
    DriveLetter = "D"
    SMPID = "4004"
}


$EnvironmentRefreshStoreDetails = [pscustomobject][ordered]@{
    Computername = "dlt-rmsbo1"
    Databasename = "ospreystoredb"
    Environment = "Delta"
},
#[pscustomobject][ordered]@{
#    Computername = "dlt-rmsbo2"
#    Databasename = "Orangebeachdb"
#    Environment = "Delta"
#},
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

$OracleEnvironmentRefreshTargetDetails = [pscustomobject][ordered]@{
    Computername = "ZET-ODBEE01"
    EnvironmentName = "Zeta"
    DatabaseName = "PRD"
    RefreshType = "ODBEE"
    SMPID = "63832","63833"
},
[pscustomobject][ordered]@{
    Computername = "DLT-ODBEE01"
    EnvironmentName = "Delta"
    DatabaseName = "PRD"
    RefreshType = "ODBEE"
    SMPID = "3960"
},
[pscustomobject][ordered]@{
    Computername = "EPS-ODBEE01"
    EnvironmentName = "Delta"
    DatabaseName = "PRD"
    RefreshType = "ODBEE"
    SMPID = "3960"
}
