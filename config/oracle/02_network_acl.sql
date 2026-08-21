-- Run as SYS in ORCLPDB. 26ai private-target hostname requires private_target=TRUE.
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'minio.labs.localhost.com', lower_port => 9000, upper_port => 9000,
    ace => XS$ACE_TYPE(privilege_list => XS$NAME_LIST('http','connect'),
      principal_name => 'LAKE', principal_type => XS_ACL.PTYPE_DB, granted => TRUE),
    private_target => TRUE);
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'minio.labs.localhost.com',
    ace => XS$ACE_TYPE(privilege_list => XS$NAME_LIST('resolve'),
      principal_name => 'LAKE', principal_type => XS_ACL.PTYPE_DB, granted => TRUE),
    private_target => TRUE);
END;
/
