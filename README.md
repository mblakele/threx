THREX - Throttled Reindexing for MarkLogic Server
===

Throttled Reindexing
---

You are working on a MarkLogic Server application,
and you need to reindex the database.
Suddenly you discover that the server is running low on disk space.
Left to itself the reindexer can paint the database into a corner,
leaving it without enough room to merge existing stands.
The long-term solution is to add more disk space,
and you should start working on that right away.
But meanwhile, Threx may be able to help.

Before you start, be sure to read the "Known Issues" section below.
Threx is reasonably robust, but it does not handle every possibly situation.
Ultimately, you will still be responsible if your database runs out of space.

Threx monitors reindexing using a scheduled task,
which checks the selected database to see if it is running out of disk space.
If the situation looks dangerous, the task pauses reindexing.
The scheduled task can also initiat merges,
to recover disk space from deleted fragments.

There is also a reporting module, so that you can monitor
what Threx is doing and why.

Installation
---

* Clone this repository.

* Set up a scheduled task using the correct path to `/threx-task.xqy`.
The scheduled task should run every 5-10 minutes.

* Optionally, set up an app server to display `threx-report.xqy`.

Usage
---

Whenever Threx detects that a complete merge would use more than
88% of the available disk space, it pauses reindexing.
This value was chosen to provide a safety factor in between task invocations.
When Threx detects that a forest has a large number of deleted fragments,
and could recover significant disk space by merging,
it starts a merge.

Threx logs various messages as it checks the database and its forests,
and modifies the reindexer state.

You may notice that Threx sometimes turns reindexing on and off
in quick succession. This is normal. Threx is slowing down reindexing,
tapping on the breaks so that ongoing merges have a chance
to relieve the shortage of disk space.

Reporting
---

The `threx-report.xqy` module displays a simple XHTML table
showing the current status of reindexing and merges.
This is similar to the MarkLogic database status page,
but focused on whether or not the current reindex and merge tasks
are likely to fill up the disk.

* `Committed %` metric is a ratio of future merge obligations
to free disk space. When this exceeds 88%, the next Threx task
will pause reindexing.
* `Merging GiB` measures the remaining GiB in current merge tasks.
* `Recoverable %` shows the ratio of deleted fragments to active fragments.
When this exceeds 3%, merging the forest may be worthwhile.

Known Issues
---

Threx considers forests on the same host and with the same data directory
to be on the same filesystem. Do not use Threx if you place multiple forests
on a single filesystem, but assign them different data directories.
In that situation, the disk space calculations will not be reliable.

Threx considers only forests attached to the target database.
Do not use Threx if other databases have active forests on the same filesystems.
In that situation, the disk space calculations will not be reliable.

Threx calculates a disk space ratio, which sometimes varies widely
from sample to sample. This happens most often as merges start or finish.
When a merge is running, Threx uses the server estimate of the final size.
This tends to reduce the disk space ratio in proportion to the merge size.
Because of this, Threx may enable reindexing after a large merge begins.

Another way to think about this is that Threx is pessimistic
about the amount of space it can recover from stands when they finally merge.
The server has better information, but this is only available
for stands that are actually merging.

Threx occasionally calculates a very high disk space ratio.
If this ratio stays over 1.0 permanently, it means that the forest
does not have enough space to merge. That is a very serious problem.
But if the high ratio is temporary and drops back down below 1.0
after a few minutes, that is not a problem.

These temporary spikes happen when a large merge has just completed,
but the old stands have not yet been deleted.
The stands being deleted are not reported in `xdmp:forest-status`,
so Threx has no way to account for them.
If the Threx task happens to catch a forest in this state,
it will pause reindexing. The next time the Threx task runs,
chances are the ratio will be back to normal and reindexing will resume.

Threx sometimes shows a zero (0) value for `GiB Merging`.
This can happen at the end of a large merge,
if the actual size of the new stand exceeds
the database projection for its final size.
Because of this risk, Threx pauses reindexing when
88% of space is committed to existing and future merges.

Security
---

More or less all of Threx's functionality depends on admin privileges.
The scheduled task must run as admin, or as a highly-privileged user
with access to admin-level functions such as
`xdmp:merge` and `admin:save-configuration`.
The reporting page could run as a less-privileged user,
but still needs access to `xdmp:forest-status` and `xdmp:forest-counts`,
among other functions.

License
---
Copyright (c) 2012 Michael Blakeley. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

The use of the Apache License does not indicate that this project is
affiliated with the Apache Software Foundation.
