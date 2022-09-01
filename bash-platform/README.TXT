A very optimistic implementation of the Buildpacks Platform spec using Bash. 

Do not expect great things ;) 

This is just enough to invoke lifecycle phases with the appropriate volumes mounted. 

The target folder is used as a scratch space, and is killed before each run.

Can be used to drive different builder images against different workspaces via -b and -w args.

