#include <stdio.h>
#include <utmp.h>

int list_stale_users()
{
        struct utmp *utent;
	int i = 0;
        printf("Checking utmp for stale users\n");
        setutent ();
        while ((utent = getutent ()) != NULL)
        {
		if (utent->ut_type == USER_PROCESS && strcmp (utent->ut_line, "???") == 0)
		{
			printf ("'%s'\n", utent->ut_user);
			i++;
		}
        }
        endutent ();
	printf("Found %i stale user(s)\n", i);
	return i;
}

int main()
{
        int i = list_stale_users();
	int j;
        for(j = 0; logout("???"); j++) {}
        if (i || j)
		printf("Logged out %i stale user(s)\n", j);
        return (j==0);
}
