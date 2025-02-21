# pg_backupsolution
A backup solution for PostgreSQL on Windows

## Intro

Maybe you are familiar wih: https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux

It is a simple, yet elegant, set of scripts to take daily, weekly and monthly backups of PostgreSQL on Linux. I wanted that on Windows!

So I asked ChatGPT...

Which gave me some pointers, but did not really do a complete job, so I took the bones from what it had given me, "windozefied" it better than "he/she/they" did and came up with this Powershell-based solution.

What I wanted to achieve was this:
* The simplicity should be kept
* Keeping the relative compatibility with the original solutions .conf-file felt essential
* Finally it should feel as "Windowsy" as possible

I think I accomplished that pretty good. I added some functionality, for example I wanted to make sure that the executables for postgre is there. I also added the possibility to save a number of monthly backups, don't know why that was not included in the original. I did remove the possibility to define a backup user to check if we are running at, it felt like i did not need that check. I did keep the yes/no variables, it is not so very Windows, but it felt more "human" and as I said I wanted to keep a relative compatibility.