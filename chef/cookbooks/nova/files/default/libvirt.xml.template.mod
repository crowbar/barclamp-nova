Base Commit: 01e090963f75c2d97c42004a3df515ae5f6e652d

0a1
> ## @@AA - force io=native for better disk/volume perf.
66a68,69
>     ## @@AA Perf - disable ballooning.
>     <memballoon model='none'/>
88c91
<                 <driver type='${driver_type}' cache='${cachemode}'/>
---
>                 <driver type='${driver_type}' cache='${cachemode}'  io='native'/>
95c98
<                 <driver type='${driver_type}' cache='${cachemode}'/>
---
>                 <driver type='${driver_type}' cache='${cachemode}' io='native' />

