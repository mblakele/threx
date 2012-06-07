THREX - Throttled Reindexing for MarkLogic Server
===

Throttled Reindexing
---

You are working on a MarkLogic Server application,
and you need to reindex the database.
Suddenly you discover that the server is running low on disk space.
Left to itself the reindexer can paint the database into a corner,
leaving it without enough room to merge existing stands.
If you act promptly, Threx can help.

Threx includes a scheduled task that checks the selected database
to see if it is running out of disk space. If the situation looks dangerous,
Threx pauses reindexing. Threx also initiate merges to recover disk space
from deleted fragments.

There is also a reporting module, so that you can monitor
what Threx is doing and why.

Installation
---

* Clone this repository.

* Set up a scheduled task using the correct path to `/threx-task.xqy`.
The scheduled task should run every 5-15 minutes.

* Optionally, set up an app server to display `threx-report.xqy`.

Usage
---

Whenever Threx detects that a complete merge would use more than
88% of the available disk space, it pauses reindexing.
This value was chosen to provide a safety factor in between task invocations.
When Threx detects that a forest has a large number of deleted fragments,
and could recover significant disk space by merging,
it starts a merge.

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

Security
---

More or less all of Presta's functionality depends on admin privileges.
The scheduled task must run as admin, or as a highly-privileged user.
Reporting could run as a less-privileged user,
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
