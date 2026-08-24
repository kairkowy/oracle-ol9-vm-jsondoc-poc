-- Run as SYS in ORCLPDB. VM1 MinIO is reached by its public IPv4 address.
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '141.148.12.16', lower_port => 9000, upper_port => 9000,
    ace => XS$ACE_TYPE(privilege_list => XS$NAME_LIST('http','connect'),
      principal_name => 'LAKE', principal_type => XS_ACL.PTYPE_DB, granted => TRUE));
END;
/
