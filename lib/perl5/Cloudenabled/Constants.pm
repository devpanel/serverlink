#!/usr/bin/perl -w
package Cloudenabled::Constants;
require Exporter;
use strict;
use warnings;
use constant CE_OP_ST_SUCCESS                  => 0;
use constant CE_OP_ST_INTERNAL_ERROR           => 1;
use constant CE_OP_ST_SIGNATURE_ERROR          => 2;
use constant CE_OP_ST_MISSING_PARAMETERS       => 3;
use constant CE_OP_ST_PARAMETER_FORMAT_ERROR   => 4;
use constant CE_OP_ST_PERMISSION_DENIED        => 5;
use constant CE_OP_ST_PARAMETER_INVALID_VALUE  => 6;
use constant CE_OP_ST_NOTHING_UPDATED          => 7;
use constant CE_OP_ST_UNKNOWN_OPERATION        => 8;
use constant CE_OP_ST_AUTHENTICATION_ERROR     => 9;
use constant CE_OP_ST_NOT_FOUND                => 10;
use constant CE_OP_ST_ERROR_PARSING_REQUEST    => 11;
use constant CE_OP_ST_HELLO_REQUIRED           => 12;
use constant CE_OP_ST_LOCAL_ERROR              => 13;

use constant CE_TASK_ST_WAITING        => 0;
use constant CE_TASK_ST_RUNNING        => 1;
use constant CE_TASK_ST_COMPLETED      => 2;
use constant CE_TASK_ST_FAILED         => 3;
use constant CE_TASK_ST_CANCELED       => 4;
use constant CE_TASK_ST_STAND_BY       => 5;
use constant CE_TASK_ST_WAITING_PARENT => 6;
use constant CE_TASK_ST_PARENT_FAILED  => 7;

use constant CE_TASK_MSG_RUN_TASKS      =>  1;
use constant CE_TASK_MSG_RUN_SHUTDOWN   =>  2;
use constant CE_TASK_MSG_RELOAD         =>  3;
use constant CE_TASK_MSG_CHANGE_POLL    =>  4;
use constant CE_TASK_MSG_CHANGE_CONFIG  =>  5;
use constant CE_TASK_MSG_SAVE_CONFIG    =>  6;
use constant CE_TASK_MSG_UPLOAD_PARAMS  =>  7;
use constant CE_TASK_MSG_NO_MESSAGES    =>  8;

use constant CE_TASK_OP_HELLO          => 1;
use constant CE_TASK_OP_GET_MSGS       => 2;
use constant CE_TASK_OP_REPORT         => 3;
use constant CE_TASK_OP_SET_RUNNING    => 4;
use constant CE_TASK_OP_RAN_INTERNAL   => 5;

use constant CE_TASK_FL_READ_STDIN                     =>     2;
use constant CE_TASK_FL_DROP_PRIVS                     =>     4;
use constant CE_TASK_FL_SEND_OUTPUT                    =>     8;
use constant CE_TASK_FL_INTERNAL_HIDDEN                =>    16;
use constant CE_TASK_FL_EXPORT_OUTPUT                  =>    64;
use constant CE_TASK_FL_IMPORT_STDIN                   =>   128;
use constant CE_TASK_FL_STDIN_BASE64                   =>   256;
use constant CE_TASK_FL_NOT_CRITICAL                   =>   512;
use constant CE_TASK_FL_SEARCH_FOR_OUTPUT_PARAMS       =>  1024;

use constant CE_FL_AUTH_IS_ADMIN      => 1;
use constant CE_FL_ACCEPT_MULT_PARAMS => 2;

use constant CE_HEADER_SIGNATURE_STR => 'X-Webenabled-Signature';
use constant CE_HEADER_SERVER_STR    => 'X-Webenabled-Server';
use constant CE_HEADER_STATUS_STR    => 'X-Webenabled-Status';
use constant CE_HEADER_SESSION_STR   => 'X-Webenabled-Session';
use constant CE_HEADER_ERRMSG_STR    => 'X-Webenabled-Errmsg';

use constant CE_TASK_MAX_OUTPUT_LEN  => 2 * 1024 * 1024;

our @ISA = (qw( Exporter ));
our @EXPORT = (qw( 
  CE_OP_ST_SUCCESS CE_OP_ST_INTERNAL_ERROR
  CE_OP_ST_SIGNATURE_ERROR CE_OP_ST_MISSING_PARAMETERS
  CE_OP_ST_PARAMETER_FORMAT_ERROR CE_OP_ST_PERMISSION_DENIED 
  CE_OP_ST_PARAMETER_INVALID_VALUE CE_OP_ST_NOTHING_UPDATED
  CE_OP_ST_UNKNOWN_OPERATION CE_OP_ST_AUTHENTICATION_ERROR
  CE_OP_ST_NOT_FOUND CE_OP_ST_ERROR_PARSING_REQUEST
  CE_OP_ST_HELLO_REQUIRED CE_OP_ST_LOCAL_ERROR

  CE_TASK_ST_WAITING CE_TASK_ST_RUNNING CE_TASK_ST_COMPLETED CE_TASK_ST_FAILED
  CE_TASK_ST_CANCELED CE_TASK_ST_STAND_BY CE_TASK_ST_WAITING_PARENT
  CE_TASK_ST_PARENT_FAILED 

  CE_TASK_MSG_RUN_TASKS CE_TASK_MSG_RUN_SHUTDOWN CE_TASK_MSG_RELOAD
  CE_TASK_MSG_CHANGE_POLL CE_TASK_MSG_CHANGE_CONFIG CE_TASK_MSG_SAVE_CONFIG
  CE_TASK_MSG_UPLOAD_PARAMS CE_TASK_MSG_NO_MESSAGES

  CE_TASK_OP_HELLO CE_TASK_OP_GET_MSGS CE_TASK_OP_REPORT
  CE_TASK_OP_SET_RUNNING CE_TASK_OP_RAN_INTERNAL

  CE_TASK_MAX_OUTPUT_LEN

  CE_TASK_FL_READ_STDIN CE_TASK_FL_DROP_PRIVS CE_TASK_FL_SEND_OUTPUT
  CE_TASK_FL_INTERNAL_HIDDEN CE_TASK_FL_EXPORT_OUTPUT
  CE_TASK_FL_IMPORT_STDIN CE_TASK_FL_STDIN_BASE64 CE_TASK_FL_NOT_CRITICAL
  CE_TASK_FL_SEARCH_FOR_OUTPUT_PARAMS

  CE_HEADER_SIGNATURE_STR CE_HEADER_SERVER_STR CE_HEADER_STATUS_STR
  CE_HEADER_SESSION_STR CE_HEADER_ERRMSG_STR
  %CE_TASKS_MSG_TYPES %CE_OP_ST_MAP %CE_TASK_ST_MAP 
));

our @EXPORT_OK = (qw(
));

our %CE_TASKS_MSG_TYPES = (
  &CE_TASK_MSG_RUN_TASKS     =>  'run tasks',
  &CE_TASK_MSG_RUN_SHUTDOWN  =>  'shutdown taskd',
  &CE_TASK_MSG_RELOAD        =>  'reload taskd',
  &CE_TASK_MSG_CHANGE_POLL   =>  'change poll interval',
  &CE_TASK_MSG_CHANGE_CONFIG =>  'change config parameter',
  &CE_TASK_MSG_SAVE_CONFIG   =>  'save config',
  &CE_TASK_MSG_UPLOAD_PARAMS =>  'upload parameters',
  &CE_TASK_MSG_NO_MESSAGES   =>  'no messages',
);

our %CE_OP_ST_MAP = (
  &CE_OP_ST_SUCCESS                   => 'Success',
  &CE_OP_ST_INTERNAL_ERROR            => 'Internal Error',
  &CE_OP_ST_SIGNATURE_ERROR           => 'Signature Error',
  &CE_OP_ST_MISSING_PARAMETERS        => 'Missing Required Parameters',
  &CE_OP_ST_PARAMETER_FORMAT_ERROR    => 'Parameter format error',
  &CE_OP_ST_PERMISSION_DENIED         => 'Permission denied',
  &CE_OP_ST_PARAMETER_INVALID_VALUE   => 'Invalid value in required parameter',
  &CE_OP_ST_NOTHING_UPDATED           => 'nothing updated on server side',
  &CE_OP_ST_UNKNOWN_OPERATION         => 'unknown operation',
  &CE_OP_ST_AUTHENTICATION_ERROR      => 'authentication error',
  &CE_OP_ST_NOT_FOUND                 => 'entry/record not found',
  &CE_OP_ST_ERROR_PARSING_REQUEST     => 'error parsing request',
  &CE_OP_ST_HELLO_REQUIRED            => 'hello required',
  &CE_OP_ST_LOCAL_ERROR               => 'local error',
);

our %CE_TASK_ST_MAP = (
  &CE_TASK_ST_WAITING          => 'WAITING',
  &CE_TASK_ST_RUNNING          => 'RUNNING',
  &CE_TASK_ST_COMPLETED        => 'COMPLETED',
  &CE_TASK_ST_FAILED           => 'FAILED',
  &CE_TASK_ST_CANCELED         => 'CANCELED',
  &CE_TASK_ST_STAND_BY         => 'UNKNOWN',
  &CE_TASK_ST_WAITING_PARENT   => 'WAITING PARENT',
  &CE_TASK_ST_PARENT_FAILED    => 'PARENT FAILED',
);

1;
