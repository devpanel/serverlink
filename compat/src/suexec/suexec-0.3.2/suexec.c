/* ====================================================================
 * Copyright (c) 1995-1997 The Apache Group.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer. 
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. All advertising materials mentioning features or use of this
 *    software must display the following acknowledgment:
 *    "This product includes software developed by the Apache Group
 *    for use in the Apache HTTP server project (http://www.apache.org/)."
 *
 * 4. The names "Apache Server" and "Apache Group" must not be used to
 *    endorse or promote products derived from this software without
 *    prior written permission.
 *
 * 5. Redistributions of any form whatsoever must retain the following
 *    acknowledgment:
 *    "This product includes software developed by the Apache Group
 *    for use in the Apache HTTP server project (http://www.apache.org/)."
 *
 * THIS SOFTWARE IS PROVIDED BY THE APACHE GROUP ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE APACHE GROUP OR
 * ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * ====================================================================
 *
 * This software consists of voluntary contributions made by many
 * individuals on behalf of the Apache Group and was originally based
 * on public domain software written at the National Center for
 * Supercomputing Applications, University of Illinois, Urbana-Champaign.
 * For more information on the Apache Group and the Apache HTTP server
 * project, please see <http://www.apache.org/>.
 *
 */

/*
 * suexec.c -- "Wrapper" support program for suEXEC behaviour for Apache
 *
 ***********************************************************************
 *
 * NOTE! : DO NOT edit this code!!!  Unless you know what you are doing,
 *         editing this code might open up your system in unexpected 
 *         ways to would-be crackers.  Every precaution has been taken 
 *         to make this code as safe as possible; alter it at your own
 *         risk.
 *
 ***********************************************************************
 *
 *
 */

#include "suexec.h"

#include <sys/param.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <errno.h>
#include <fcntl.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>


#if defined(PATH_MAX)
#define AP_MAXPATH PATH_MAX
#elif defined(MAXPATHLEN)
#define AP_MAXPATH MAXPATHLEN
#else
#define AP_MAXPATH 8192
#endif

#define AP_ENVBUF 256

#define	EXEC_DEFAULT	0
#define	EXEC_PHP	1
#define	EXEC_FCGI	2

extern char **environ;
static FILE *log;

static char *safe_env_lst[] =
{   
    "AUTH_TYPE",
    "CONTENT_LENGTH",
    "CONTENT_TYPE",
    "DATE_GMT",
    "DATE_LOCAL",
    "DOCUMENT_NAME",
    "DOCUMENT_PATH_INFO",
    "DOCUMENT_ROOT",
    "DOCUMENT_URI",
    "FILEPATH_INFO",
    "GATEWAY_INTERFACE",
    "HTTPS",
    "LAST_MODIFIED",
    "PATH_INFO",
    "PATH_TRANSLATED",
    "QUERY_STRING",
    "QUERY_STRING_UNESCAPED",
    "REMOTE_ADDR",
    "REMOTE_HOST",
    "REMOTE_IDENT",
    "REMOTE_PORT",
    "REMOTE_USER",
    "REDIRECT_QUERY_STRING",
    "REDIRECT_STATUS",
    "REDIRECT_URL",
    "REQUEST_METHOD",
    "REQUEST_URI",
    "SCRIPT_FILENAME",
    "SCRIPT_NAME",
    "SCRIPT_URI",
    "SCRIPT_URL",
    "SERVER_ADDR",
    "SERVER_ADMIN",
    "SERVER_NAME",
    "SERVER_PORT",
    "SERVER_PROTOCOL",
    "SERVER_SOFTWARE",
    "SOURCE_CHARSET",
    "UNIQUE_ID",
    "USER_NAME",
    "TZ",
    NULL
};

static char *allow_suffixes[] =
{
    ".pl",
    ".cgi",
    ".php",
    ".phtml",
    ".py",
    ".rb",
    NULL
};

#define CGI_PERSONAL	1	/* bit 0 -- enable/disable personal scripts */
#define CGI_MAIL	2
#define CGI_MYSQL	4
#define CGI_FASTCGI	128	/* bit 7 -- special:
				   allows to execute /usr/local/bin/fastcgi */

struct common_cgi_t {
	char *name;
	unsigned char type;
} common_cgi_lst[] =
{
    { "qmailadmin",	CGI_MAIL	},
    { "squirrelmail",	CGI_MAIL	},
    { "phpmyadmin",	CGI_MYSQL	},
    { "fastcgi",	CGI_FASTCGI	},
    { NULL,		0		}
};


static void err_output(const char *fmt, va_list ap)
{
    time_t timevar;
    struct tm *lt;

    if (!log)
	if ((log = fopen(LOG_EXEC, "a")) == NULL) {
	    fprintf(stderr, "failed to open log file\n");
	    perror("fopen");
	    exit(1);
	}

    time(&timevar);
    lt = localtime(&timevar);
    
    fprintf(log, "[%.2d:%.2d:%.2d %.2d-%.2d-%.2d]: ", lt->tm_hour, lt->tm_min,
	    lt->tm_sec, lt->tm_mday, (lt->tm_mon + 1), 1900 + lt->tm_year);
    
    vfprintf(log, fmt, ap);

/*    fflush(log); */
    return;
}

void log_err(const char *fmt, ...)
{
#ifdef LOG_EXEC
    va_list     ap;

    va_start(ap, fmt);
    err_output(fmt, ap);
    va_end(ap);
#endif /* LOG_EXEC */
    return;
}

void clean_env() 
{
    char pathbuf[512];
    char **cleanenv;
    char **ep;
    int cidx = 0;
    int idx;
    

    if ((cleanenv = (char **)calloc(AP_ENVBUF, sizeof(char *))) == NULL) {
	log_err("failed to malloc env mem\n");
	exit(120);
    }
    
    for (ep = environ; *ep && cidx < AP_ENVBUF; ep++) {
	if (!strncmp(*ep, "HTTP_", 5) || !strncmp(*ep, "CHARSET", 7)) {
	    cleanenv[cidx] = *ep;
	    cidx++;
	}
	else {
	    for (idx = 0; safe_env_lst[idx]; idx++) {
		if (!strncmp(*ep, safe_env_lst[idx], strlen(safe_env_lst[idx]))) {
		    cleanenv[cidx] = *ep;
		    cidx++;
		    break;
		}
	    }
	}
    }

    sprintf(pathbuf, "PATH=%s", SAFE_PATH);
    cleanenv[cidx] = strdup(pathbuf);
    cleanenv[++cidx] = NULL;
	    
    environ = cleanenv;
}

void set_one_limit(int resource, int limit)
{
    struct rlimit rl;

    if (!getrlimit(resource, &rl))
    if (limit > rl.rlim_max) return;

    rl.rlim_max = rl.rlim_cur = limit;
    if (setrlimit(resource, &rl)) {
	log_err("cannot set resource limits: %s\n", strerror(errno));
	exit(121);
    }
}

void fix_binary_transfer(char *script, struct stat *prg_info)
{
    char *p, *q;
    FILE *f;
    int size, size2;
    int i;
    char buffer[64];

    if ((f = fopen(script, "r")) == NULL)
	return;

    fread(buffer, 64, 1, f);
    if (!strncmp(buffer, "#!/usr/bin/perl\r\n", 17)
		|| !strncmp(buffer, "#!/usr/local/bin/perl\r\n", 23)
		|| !strncmp(buffer, "#!/usr/local/bin/php\r\n", 22)) {
	log_err("%s was uploaded in binary mode\n", script);

	if ((size = prg_info->st_size) > 1024000) {
	    log_err("script is too large(%d bytes), exiting\n", size);
	    exit(150);
	    }
	if ((p = malloc(size)) == NULL) {
	    log_err("malloc(%d) failed, exiting\n", size);
	    exit(150);
	    }
	if ((q = malloc(size)) == NULL) {
	    log_err("malloc(%d) failed, exiting\n", size);
	    exit(150);
	    }

	fseek(f, 0, SEEK_SET);
	if (fread(p, size, 1, f) != 1) {
	    log_err("couldn't read file: %s\n", strerror(errno));
	    exit(150);
	    }
	fclose(f);

        if ((f = fopen(script, "w")) == NULL) {
	    log_err("couldn't open file '%s': %s\n", script, strerror(errno));
	    exit(150);
            }

	size2 = 0;
	for (i=0; i < size; i++) {
	    if (p[i] == '\r') continue;
	    q[size2++] = p[i];
	    }

	if (fwrite(q, size2, 1, f) != 1) {
	    log_err("couldn't write file: %s\n", strerror(errno));
	    exit(150);
	    }
	free(p);
	free(q);
	log_err("%s: invalid transfer mode fixed\n", script);
	}
    fclose(f);
}

unsigned char get_common_type(const char *cmd) {
    unsigned int idx = 0;
    for (idx = 0; common_cgi_lst[idx].name; idx++)
        if (!strncmp(cmd, common_cgi_lst[idx].name, strlen(common_cgi_lst[idx].name)))
            return common_cgi_lst[idx].type;
    return 0;
}

unsigned char get_config(const uid_t uid) {
    int fd;
    struct stat buf;
    struct flock lock;
    unsigned char config = 0;

    if (stat(SUEXEC_MAP_FILE, &buf) != 0) {
        log_err("couldn't stat(2) " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
        return 0;
    }
    if (!(
            (buf.st_mode == (S_IFREG | S_IRUSR | S_IWUSR))
            && !buf.st_uid && !buf.st_gid
        )) {
        log_err(SUEXEC_MAP_FILE " must be regular file owned by root:root with 0600 permissions\n");
        return 0;
    }

    if (buf.st_size < uid) return 1; /* there is no information */

    if ((fd = open(SUEXEC_MAP_FILE, O_RDONLY)) == -1) {
        log_err("couldn't open(2) " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
        return 0;
    }

    (void) memset(&lock, 0, sizeof(struct flock));
    lock.l_type = F_RDLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = uid;
    lock.l_len = 1;

    if (fcntl(fd, F_SETLK, &lock) != 0) {
        log_err("couldn't lock " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
        goto bail_out;
    }

    if (uid != lseek(fd, uid, SEEK_SET)) {
        log_err("couldn't lseek(2) " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
        goto bail_out;
    }

    if (read(fd, &config, 1) != 1) {
        log_err("error during read(2) " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
	config = 0;
    }

bail_out:
    /* I don't like gotos, but here it just adds the simplicity to the code */
    if (close(fd) != 0) { /* we don't want to leak open fd */
        log_err("couldn't close(2) " SUEXEC_MAP_FILE ": %s\n", strerror(errno));
        exit(200);
    }
    return config;
}

const char *get_interpreter(const char *default_interpreter, const char *config_dir) {
    char *result = NULL;
    char *name = NULL;
    struct stat buf;
    if (!default_interpreter || !*default_interpreter) {
        log_err("get_interpreter(): no default interpreter is defined\n");
        exit(200);
    }
    if ((name = strrchr(default_interpreter, '/')) == NULL || !(++name)) {
        log_err("get_interpreter(): '%s' is not absolute pathname\n",
            default_interpreter);
        exit(200);
    }
    if (asprintf(&result, "%s/bin/%s-cgi", config_dir, name) < 0) {
        log_err("get_interpreter(): asprintf() error during the path composition\n");
        exit(200);
    }
    if (stat(result, &buf) != 0) {
	/* Now try plain interpreter with no -cgi suffix */
	result[strlen(result)-4] = 0;
    	if (stat(result, &buf) != 0) {
        	free(result);
    		if (asprintf(&result, "%s-cgi", default_interpreter) < 0) {
		        log_err("get_interpreter(): asprintf() error during the path composition\n");
		        exit(200);
    		}
		/* Try default interpreter with the -cgi suffix */
    		if (stat(result, &buf) != 0) {
			free(result);
			/* Fallback to the default */
	        	return default_interpreter;
		}
	}
    }

    return result;
}

int main(int argc, char *argv[])
{
    int userdir=0;          /* ~userdir flag             */
    uid_t uid;              /* user information          */
    gid_t gid;              /* target group placeholder  */
    gid_t trusted_gid;	    /* the gid we trust for directory ownership */
    char *target_uname;     /* target user name          */
    char *target_gname;     /* target group name         */
    char *target_homedir;   /* target home directory     */
    char *actual_uname;     /* actual user name          */
    char *actual_gname;     /* actual group name         */
    char *prog;             /* name of this program      */
    char *cmd;              /* command to be executed    */
    char cwd[AP_MAXPATH];   /* current working directory */
    char dwd[AP_MAXPATH];   /* docroot working directory */
    struct passwd *pw;      /* password entry holder     */
    struct group *gr;       /* group entry holder        */
    unsigned char config;   /* CGI permissions bit mask  */
    struct stat dir_info;   /* directory info holder     */
    struct stat prg_info;   /* program info holder       */
    int found, restricted_userdir=0, sfx_length;
    int common_cgi = 0;
    char **sfx;
    int special_exec_needed = EXEC_DEFAULT;
    char *doc_root_1 = NULL;
#ifdef DOC_ROOT_2
    char *doc_root_2 = NULL;
#endif

    /*
     * If there are a proper number of arguments, set
     * all of them to variables.  Otherwise, error out.
     */
    prog = argv[0];
    if (argc < 4) {
	log_err("too few arguments\n");
	exit(101);
    }
    target_uname = argv[1];
    target_gname = argv[2];
    cmd = argv[3];

    /*
     * Check existence/validity of the UID of the user
     * running this program.  Error out if invalid.
     */
    uid = getuid();
    trusted_gid = getgid();
    if ((pw = getpwuid(uid)) == NULL) {
	log_err("invalid uid: (%ld)\n", uid);
	exit(102);
    }
    
    /*
     * Check to see if the user running this program
     * is the user allowed to do so as defined in
     * suexec.h.  If not the allowed user, error out.
     */
    if (strcmp(HTTPD_USER, pw->pw_name)) {
#ifdef HTTPD_USER2 /* Are we are in transition to _httpd ? */
	if (strcmp(HTTPD_USER2, pw->pw_name)) {
#endif
	log_err("user mismatch (%s)\n", pw->pw_name);
	exit(103);
#ifdef HTTPD_USER2
	}
#endif
    }

    /*
     * Check for a leading '/' (absolute path) in the command to be executed,
     * or attempts to back up out of the current directory,
     * to protect against attacks.  If any are
     * found, error out.  Naughty naughty crackers.
     */
    if (
	    (cmd[0] == '/') ||
	    (! strncmp (cmd, "../", 3)) ||
	    (strstr (cmd, "/../") != NULL)
       ) {
	log_err("invalid command (%s)\n", cmd);
	exit(104);
    }

    /*
     * Check to see if this is a ~userdir request.  If
     * so, set the flag, and remove the '~' from the
     * target username.
     */
    if (!strncmp("~", target_uname, 1)) {
	target_uname++;
	userdir = 1;
    }

    /*
     * Error out if the target username is invalid.
     */
    if (strspn(target_uname, "1234567890") != strlen(target_uname)) {
        if ((pw = getpwnam(target_uname)) == NULL) {
            log_err("invalid target user name: (%s)\n", target_uname);
            exit(105);
	}
    }
    else {
        if ((pw = getpwuid(atoi(target_uname))) == NULL) {
            log_err("invalid target user id: (%s)\n", target_uname);
            exit(121);
        }
    }

    /*
     * Error out if the target group name is invalid.
     */
    if (strspn(target_gname, "1234567890") != strlen(target_gname)) {
	if ((gr = getgrnam(target_gname)) == NULL) {
	    log_err("invalid target group name: (%s)\n", target_gname);
	    exit(106);
	}
	gid = gr->gr_gid;
	actual_gname = strdup(gr->gr_name);
    }
    else {
	gid = atoi(target_gname);
	actual_gname = strdup(target_gname);
    }

    if (gid != pw->pw_gid) {
	log_err("target gid doesn't match the user's primary gid: (%d/%d)\n",
		pw->pw_uid, gid);
	exit(106);
    }

    /*
     * Save these for later since initgroups will hose the struct
     */
    uid = pw->pw_uid;
    actual_uname = strdup(pw->pw_name);
    target_homedir = strdup(pw->pw_dir);

    /*
     * Log the transaction here to be sure we have an open log 
     * before we setuid().
     */
    log_err("uid: (%s/%s) gid: (%s/%s) %s\n",
             target_uname, actual_uname,
             target_gname, actual_gname,
             cmd);

    if (getcwd(cwd, AP_MAXPATH) == NULL) {
        log_err("cannot get current working directory\n");
        exit(111);
    }

    /*
     * Let's figure out what supplied DOC_ROOTs are
     */
    if ((doc_root_1 = malloc(AP_MAXPATH+1)) == NULL) {
       log_err("doc_root_1 malloc(%d) failed, exiting\n", AP_MAXPATH+1);
       exit(150);
    }

#ifdef DOC_ROOT_2
    if ((doc_root_2 = malloc(AP_MAXPATH+1)) == NULL) {
       log_err("doc_root_2 malloc(%d) failed, exiting\n", AP_MAXPATH+1);
       exit(150);
    }
#endif

    if (chdir(DOC_ROOT_1) == 0 && getcwd(doc_root_1, AP_MAXPATH)
#ifdef DOC_ROOT_2
       && chdir(DOC_ROOT_2) == 0 && getcwd(doc_root_2, AP_MAXPATH)
#endif
       ) {
       if (chdir(cwd) != 0) {
          log_err("cannot change current dir back to '%s', exiting\n", cwd);
          exit(150);
       }
    }
    else {
       log_err("error during getting real paths of DOC_ROOTs, exiting\n");
       exit(150);
    }

    common_cgi = (
	!strncmp(cwd, doc_root_1, strlen(doc_root_1))
#ifdef DOC_ROOT_2
        || !strncmp(cwd, doc_root_2, strlen(doc_root_2))
#endif
	);

    free(doc_root_1);
#ifdef DOC_ROOT_2
    free(doc_root_2);
#endif

    /*
     * Error out if attempt is made to execute as root or as
     * a UID less than UID_MIN.  Tsk tsk.
     */
    if ( uid==0 ||
        uid < UID_MIN ) {
	log_err("cannot run as forbidden uid (%d/%s)\n", uid, cmd);
	exit(107);
    }

    /*
     * Error out if attempt is made to execute as root group
     * or as a GID less than GID_MIN.  Tsk tsk.
     */
    if ((gid == 0) ||
        (gid < GID_MIN)) {
	log_err("cannot run as forbidden gid (%d/%s)\n", gid, cmd);
	exit(108);
    }

    if ((config = get_config(uid)) == 0) {
	log_err("CGI scripts are disabled for uid (%d/%s)\n", uid, cmd);
        exit(201);
    }

    if (common_cgi) {
	unsigned char common_type = get_common_type(cmd);
	if ((config & common_type) != common_type) {
	    log_err("common_cgi of type (%u) is forbidden for uid (%d/%s)\n", common_type, uid, cmd);
	    exit(201);
	}

	/* this is a hack since FastCGI execution has nothing to do with
           the CommonCGI interface but we are handling it here since we
	   need this for a special configuration when the wrapper is located
	   outside user homedir
	 */
	if (common_type == CGI_FASTCGI) {
        	if (!(config & 1)) {
		    log_err("despite that FastCGI is allowed personal CGI scripts are forbidden for uid (%d/%s)\n", uid, cmd);
		    exit(201);
        	}
		special_exec_needed = EXEC_FCGI;
	}
    }
    else {
        if (!(config & 1)) {
	    log_err("personal CGI scripts are forbidden for uid (%d/%s)\n", uid, cmd);
	    exit(201);
        }
    }

    /*
     * Change UID/GID here so that the following tests work over NFS.
     *
     * Initialize the group access list for the target user,
     * and setgid() to the target group. If unsuccessful, error out.
     */
    if ( (setgid(gid)) != 0 ) {
        log_err("failed to setgid (%ld: %s/%s)\n", gid, cwd, cmd);
        exit(109);
    }

    /*setgroups(0, NULL);*/
    initgroups(actual_uname,gid);

    /*
     * setuid() to the target user.  Error out on fail.
     */
    if ((setuid(uid)) != 0) {
	log_err("failed to setuid (%ld: %s/%s)\n", uid, cwd, cmd);
	exit(110);
    }

    /*
     * Get the current working directory, as well as the proper
     * document root (dependant upon whether or not it is a
     * ~userdir request).  Error out if we cannot get either one,
     * or if the current working directory is not in the docroot.
     * Use chdir()s and getcwd()s to avoid problems with symlinked
     * directories.  Yuck.
     */
    if (getcwd(cwd, AP_MAXPATH) == NULL) {
        log_err("cannot get current working directory\n");
        exit(111);
    }

    if (!common_cgi) {
        if (chdir(target_homedir) != 0)
	{
		log_err("cannot change directory to homedir (%s)\n",
				target_homedir);
		exit(112);
	}

	if  ((chdir(USERDIR_SUFFIX) != 0) ||
	    (getcwd(dwd, AP_MAXPATH) == NULL))
	{
		restricted_userdir = 1;
	}

	if (chdir(cwd) != 0)
        {
		log_err("cannot change directory back to '%s'\n", 
				cwd);
		exit(112);
        }

        if (!restricted_userdir && strncmp(cwd, dwd, strlen(dwd))) {
            restricted_userdir = 1;
            if (((chdir(target_homedir)) != 0) ||
                ((chdir(RESTRICTED_USERDIR_SUFFIX)) != 0) ||
	        ((getcwd(dwd, AP_MAXPATH)) == NULL) ||
                ((chdir(cwd)) != 0))
            {
                log_err("cannot get restricted docroot information (%s/%s)\n", 
				target_homedir, RESTRICTED_USERDIR_SUFFIX);
                exit(112);
            }
            if (strncmp(cwd, dwd, strlen(dwd))) {
                log_err("command not in docroot (%s/%s)\n", cwd, cmd);
                exit(114);
            }
        }

        if ( restricted_userdir ) {
            found = 0;
            for ( sfx=allow_suffixes; *sfx; sfx++ ) {
                sfx_length = strlen(*sfx);
                if ( sfx_length < strlen(cmd) &&
                        !strncmp(cmd+strlen(cmd)-sfx_length,*sfx,sfx_length)) {
                    found = 1;
                    break;
                    }
                }
        if ( !found ) {
             log_err("command with this extention is not allowed in this directory\n");
             exit(114);
             }
        }
    }

    /*
     * Stat the cwd and verify it is a directory, or error out.
     */
    if (((lstat(cwd, &dir_info)) != 0) || !(S_ISDIR(dir_info.st_mode))) {
	log_err("cannot stat directory: (%s)\n", cwd);
	exit(115);
    }

    /*
     * Error out if cwd is writable by others.
     */
    if ((dir_info.st_mode & S_IWOTH) || (dir_info.st_mode & S_IWGRP)) {
	log_err("directory is writable by others: (%s)\n", cwd);
	exit(116);
    }

    /*
     * Error out if we cannot stat the program.
     */
    if (((stat(cmd, &prg_info)) != 0) || (!S_ISREG(prg_info.st_mode))) {
	log_err("cannot stat program: (%s)\n", cmd);
	exit(117);
    }

    /*
     * Error out if the program is writable by others.
     */
    if ((prg_info.st_mode & S_IWOTH) || (prg_info.st_mode & S_IWGRP)) {
	log_err("file is writable by others: (%s/%s)\n", cwd, cmd);
	exit(118);
    }

    /*
     * Error out if the file is setuid or setgid.
     */
    if ((prg_info.st_mode & S_ISUID) || (prg_info.st_mode & S_ISGID)) {
	log_err("file is either setuid or setgid: (%s/%s)\n",cwd,cmd);
	exit(119);
    }

    /*
     * Error out if the target name/group is different from
     * the name/group of the cwd or the program.
     */
    if (!common_cgi)
    if ((uid != dir_info.st_uid) ||
	(gid != dir_info.st_gid && dir_info.st_gid != trusted_gid) ||
	(uid != prg_info.st_uid) ||
	(gid != prg_info.st_gid))
    {
	log_err("target uid/gid (%ld/%ld) mismatch with directory (%ld/%ld) or program (%ld/%ld)\n",
		 uid, gid,
		 dir_info.st_uid, dir_info.st_gid,
		 prg_info.st_uid, prg_info.st_gid);
	exit(120);
    }

    if ( /* if supplied cmd is PHP script, check for hashbang and set the flag */
           (strlen(cmd) > 4 && !strcmp(&cmd[strlen(cmd) - 4],".php")) ||
           (strlen(cmd) > 6 && !strcmp(&cmd[strlen(cmd) - 6],".phtml"))
       ) {
	FILE *f;
	char buffer[3];

        if ((f = fopen(cmd,"r")) == NULL) {
    	    log_err("couldn't open file '%s': %s\n", cmd, strerror(errno));      
    	    exit(150);
        }

        if (!fread(buffer,2,1,f)) {
    	    log_err("couldn't read file '%s': %s\n", cmd, strerror(errno));      
    	    exit(150);
        }

        if (fclose(f)) {
    	    log_err("couldn't close file '%s': %s\n", cmd, strerror(errno));      
    	    exit(150);
        }

	if (buffer[0] != '#' || buffer[1] != '!') {
	/*
         * This doesn't seems to be a valid shell script, so we will try to
         * execute it via PHP interpreter manually
         */
         special_exec_needed = EXEC_PHP;
	}
    }

    if (!(prg_info.st_mode & S_IXUSR) && (special_exec_needed != EXEC_PHP)) {
	log_err("file is not executable: (%s/%s)\n",cwd,cmd);

	if ( (prg_info.st_mode & 0777)==0644 && (
            ( strlen(cmd) > 4 && ( !strcmp(&cmd[strlen(cmd) - 4],".cgi") ) ) ||
            ( strlen(cmd) > 4 && ( !strcmp(&cmd[strlen(cmd) - 4],".php") ) ) ||
            ( strlen(cmd) > 6 && ( !strcmp(&cmd[strlen(cmd) - 6],".phtml") ) )
	) ) {

            if (!chmod(cmd, 0700))
                log_err("chmod of %s succeeded\n", cmd);
            else 
                exit(119);
          }
    }

    /*
     * Set the resource limits.
     */
    set_one_limit(RLIMIT_NPROC, SUEXEC_RLIMIT_NPROC);
    set_one_limit(RLIMIT_AS, SUEXEC_RLIMIT_DATA);
    set_one_limit(RLIMIT_NOFILE, SUEXEC_RLIMIT_NOFILE);

    /* we don't need this limit for FCGI since such scripts are controlled
       by mod_fcgid */
    if (special_exec_needed != EXEC_FCGI)
    	set_one_limit(RLIMIT_CPU, SUEXEC_RLIMIT_CPU);

    /*
     * these users are annoying
     */
    fix_binary_transfer(cmd, &prg_info);

    clean_env();

    if (special_exec_needed != EXEC_FCGI)
	alarm(3610);

    /* 
     * Be sure to close the log file so the CGI can't
     * mess with it.  If the exec fails, it will be reopened 
     * automatically when log_err is called.
     */
    fclose(log);
    log = NULL;
    
    umask(022);
    /*
     * Execute the command, replacing our image with its own.
     */
    switch (special_exec_needed) {
	case EXEC_PHP:	/* execute PHP via interpreter manually */
			{
				const char *interpreter = get_interpreter(PHP_BINARY, target_homedir);
				char *new_argv[] = { interpreter, cmd, NULL };
        /* work around for the --force-cgi-redirect PHP feature */
        setenv("REDIRECT_STATUS", "200", 0);

        execv(interpreter, new_argv);
			}
			break;
	case EXEC_FCGI: /* we exactly know what we should execute */
			execv(FCGI_BINARY, &argv[3]);
			break;

	case EXEC_DEFAULT:
			execv(cmd, &argv[3]);
			break;

	default:
			log_err("Internal suEXEC error: exec type is not implemented");
    }

    /*
     * Oh well, log the failure and error out.
     */
    perror("exec");
    exit(255);
}
