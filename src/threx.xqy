xquery version "1.0-ml";

(:
 : Copyright (c) 2012 Michael Blakeley. All Rights Reserved.
 :
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 :
 : http://www.apache.org/licenses/LICENSE-2.0
 :
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :
 : The use of the Apache License does not indicate that this project is
 : affiliated with the Apache Software Foundation.
 :
 :)
module namespace rx="com.blakeley.threx" ;

declare default function namespace "http://www.w3.org/2005/xpath-functions";

import module namespace admin = "http://marklogic.com/xdmp/admin"
  at "/MarkLogic/admin.xqy";

declare namespace fs="http://marklogic.com/xdmp/status/forest";

declare variable $CONFIG := admin:get-configuration() ;

declare variable $LABEL := 'com.blakeley.threx' ;

(: Tuning these limits boils down to...
 : How much trouble can we get into in between scheduled task runs?
 :)

declare variable $LIMIT-DELETED := 0.03 ;

declare variable $LIMIT-SPACE := 0.88 ;

declare variable $MUTEX := concat('.mutex/', $LABEL) ;

declare function rx:log($msg as item()*, $level as xs:string)
as empty-sequence()
{
  xdmp:log(text { $LABEL, $msg }, $level)
};

declare function rx:debug($msg as item()*)
as empty-sequence()
{
  xdmp:log(text { $LABEL, $msg }, 'debug')
};

declare function rx:info($msg as item()*)
as empty-sequence()
{
  xdmp:log(text { $LABEL, $msg }, 'info')
};

declare function rx:notice($msg as item()*)
as empty-sequence()
{
  xdmp:log(text { $LABEL, $msg }, 'notice')
};

declare function rx:warning($msg as item()*)
as empty-sequence()
{
  xdmp:log(text { $LABEL, $msg }, 'warning')
};

declare function rx:device-forests-have(
  $fs-list as element(fs:forest-status)*)
as xs:unsignedLong
{
  sum((0, $fs-list[1]/fs:device-space))
};

declare function rx:device-forests-need(
  $fs-list as element(fs:forest-status)*)
as xs:unsignedLong
{
  let $merging := data(
    $fs-list/fs:merges/fs:merge/fs:input-stands/fs:stand-id)
  return sum(
    (0,
      (: At some point these stands will need to merge too,
       : so we budget the space.
       :)
      $fs-list/fs:stands/fs:stand[
        fs:stand-kind eq 'Active'
        and not(fs:stand-id = $merging)]/fs:disk-size,
      (: Budget space to finish any merges already in progress. :)
      sum($fs-list/fs:merges/fs:merge/fs:final-size)
      - sum($fs-list/fs:merges/fs:merge/fs:current-size)))
};

declare function rx:db-forest-device-map(
  $db as xs:unsignedLong)
as map:map
{
  let $m := map:map()
  let $put := (
    for $fs in xdmp:forest-status(xdmp:database-forests($db))
    let $key := concat($fs/fs:host-id, ':', $fs/fs:data-dir)
    return map:put($m, $key, (map:get($m, $key), $fs)))
  return $m
};

declare function rx:forest-deleted-ratio(
  $fc as element(fs:forest-counts))
as xs:double
{
  sum($fc/fs:stands-counts/fs:stand-counts/fs:deleted-fragment-count)
  div
  sum($fc/fs:stands-counts/fs:stand-counts/fs:active-fragment-count)
};

declare function rx:db-level(
  $db as xs:unsignedLong)
as xs:double
{
  (:
   : Aggregate forest sizes across devices.
   : When checking the size limit, allow for in-progress merges.
   :)
  max(
    let $m := rx:db-forest-device-map($db)
    for $key in map:keys($m)
    let $fs-list := map:get($m, $key)
    let $need := rx:device-forests-need($fs-list)
    let $have := rx:device-forests-have($fs-list)
    let $ratio := ($need div $have)
    let $DEBUG := if ($ratio lt 1) then () else rx:debug(
      ('high ratio', $ratio,
        normalize-space(xdmp:quote($fs-list))))
    return $ratio)
};

declare function rx:is-forest-merge-ready(
  $fs as element(fs:forest-status),
  $fc as element(fs:forest-counts))
as xs:unsignedLong?
{
  (: Note that this calculation completely ignores the number of stands.
   : Forests do a fine job of managing that by themselves.
   : TODO Should this code also consider $LIMIT-SPACE?
   :)
  let $id := $fs/fs:forest-id
  let $ratio := rx:forest-deleted-ratio($fc)
  let $d := rx:debug(
    ('is-forest-merge-ready', $fs/fs:forest-name,
      ($ratio gt $LIMIT-DELETED), $ratio))
  where $ratio gt $LIMIT-DELETED
  return $id
};

(: TODO refactor to avoid repeated code :)
declare function rx:report(
  $db as xs:unsignedLong)
as element()
{
  (: report disk-size ratio with merge status :)
  <table xmlns="http://www.w3.org/1999/xhtml" width="85%">
  {
    element caption {
      element p {
      "Reindexing is",
      if (admin:database-get-reindexer-enable($CONFIG, $db)) then 'enabled'
      else 'paused',
      'as of', substring-before(string(current-dateTime()), '.') },
      element p {
        'Commit maximum', concat(100 * $LIMIT-SPACE, '%'), '-',
        'Recovery minimum', concat(100 * $LIMIT-DELETED, '%') } },
    element tr {
      for $i in (
        'Committed-%', 'Committed-GiB', 'Available-GiB',
        'Merging-GiB', 'Merge-MB/sec',
        'Recoverable-%', 'Recover?', 'Forests')
      return element th { translate($i, '-', codepoints-to-string(160)) } },
    let $m := rx:db-forest-device-map($db)
    for $key at $x in map:keys($m)
    let $fs-list := map:get($m, $key)
    let $have := rx:device-forests-have($fs-list)
    let $need := rx:device-forests-need($fs-list)
    let $ratio := xs:double($need div $have)
    let $DEBUG := if ($ratio lt 1) then () else rx:debug(
      ('high ratio', $ratio, $need, $have,
        normalize-space(xdmp:quote($fs-list))))
    let $deleted := (
      for $fs in $fs-list return rx:forest-deleted-ratio(
        xdmp:forest-counts($fs/fs:forest-id, 'stands-counts')))
    let $deleted-fmt := format-number(
      round-half-to-even(100 * $deleted, 1), "0.0")
    order by $ratio descending, $deleted descending
    return element tr {
      for $i in (
        format-number(round-half-to-even(100 * $ratio, 1), "0.0"),
        format-number($need div 1024, "#,###,##0"),
        format-number($have div 1024, "#,###,##0"))
      return element td {
        attribute style {
          "text-align: right;"[$i castable as xs:double] },
        $i },
      for $i in (
        if (empty($fs-list/fs:merges/fs:merge)) then ''
        else format-number(
            (sum($fs-list/fs:merges/fs:merge/fs:final-size)
              - sum($fs-list/fs:merges/fs:merge/fs:current-size))
            div 1024, "#,###,##0"),
        if (empty($fs-list/fs:merges/fs:merge)) then ''
        else format-number(
          round(sum($fs-list/fs:merge-read-rate)), '##0'),
        $deleted-fmt)
      return element td {
        attribute style {
          "text-align: right;"[$i castable as xs:double] },
        $i },
      element td {
        attribute style { "text-align: center;" },
        'x'[$deleted gt 0.03] },
      element td {
        attribute style {
          'width: 33%;',
          'margin-right: 1em;',
          'margin-left: 1em;',
          'padding-right: 1em;',
          'padding-left: 1em;' },
        $fs-list/fs:forest-name/string() }}
  }
  </table>
};

declare function rx:maybe-merge(
  $db as xs:unsignedLong)
as empty-sequence()
{
  (: Should we merge any forests?
   : Make sure at least one disk looks fairly full.
   : Consider forests that are not already merging,
   : and that have a significant number of deleted fragments.
   :)
  rx:debug(('maybe-merge', xdmp:database-name($db))),
  let $db-level := rx:db-level($db)
  where $db-level gt $LIMIT-SPACE
  return (
    let $forest-list := data(
      for $fs in xdmp:forest-status(xdmp:database-forests($db))[
        not(fs:merges/fs:merge
          or fs:reindexing/xs:boolean(.)) ]
      where rx:is-forest-merge-ready(
        $fs, xdmp:forest-counts($fs/fs:forest-id, 'stands-counts'))
      return $fs/fs:forest-id)
    where $forest-list
    return xdmp:merge(
      <options xmlns="xdmp:merge">
      {
        rx:notice(
          ('starting merge on database', xdmp:database-name($db),
            'level', format-number($db-level, "0.00"),
            'forests', count($forest-list), xdmp:forest-name($forest-list))),
        element forests {
          for $c in $forest-list return element forest { $c } }
      }
      </options>))
};

declare function rx:maybe-disable(
  $db as xs:unsignedLong)
as empty-sequence()
{
  (: We know the reindexer is enabled on this database. :)
  let $db-level := rx:db-level($db)
  return (
    if ($db-level le $LIMIT-SPACE) then (
      rx:debug(
        ('proceeding with reindex on database', xdmp:database-name($db),
          'level', format-number($db-level, "0.00"))))
    else (
      rx:notice(
        ('disabling reindexing on database', xdmp:database-name($db),
        'level', format-number($db-level, "0.00"))),
      xdmp:set(
        $CONFIG, admin:database-set-reindexer-enable($CONFIG, $db, false())),
      admin:save-configuration($CONFIG)))
};

declare function rx:maybe-enable(
  $db as xs:unsignedLong)
as empty-sequence()
{
  (: We know the reindexer is disabled on this database,
   : but double-check anyhow.
   : Should we enable reindexing?
   : When things look iffy, do nothing.
   : This is a scheduled task, so it will run again soon.
   :)
  rx:debug(('maybe-enable', xdmp:database-name($db))),
  let $fs-list := xdmp:forest-status(xdmp:database-forests($db))
  where not($fs-list/reindexing/xs:boolean(.))
  return (
    (: Shall we enable reindexing? :)
    let $db-level := rx:db-level($db)
    return (
      if ($db-level gt $LIMIT-SPACE) then rx:info(
        ('reindexing paused on database', xdmp:database-name($db),
          'level', format-number($db-level, "0.00")))
      (: Time to let the reindexer proceed. :)
      else (
        rx:notice(
          ('re-enabling reindexing on database', xdmp:database-name($db),
        'level', format-number($db-level, "0.00"))),
        xdmp:set(
          $CONFIG, admin:database-set-reindexer-enable($CONFIG, $db, true())),
        admin:save-configuration($CONFIG))))
};

declare function rx:maybe(
  $db as xs:unsignedLong)
as empty-sequence()
{
  rx:debug(
    ('starting: reindex =', admin:database-get-reindexer-enable($CONFIG, $db),
      'merge =', count(xdmp:merging()))),
  (: Make sure we have exclusive control,
   : at least as far as other copies of this scheduled task go.
   :)
  xdmp:lock-for-update($MUTEX),
  (: Stop reindexing if running? Enable if disabled?
   : Merge or do nothing?
   :)
  if (admin:database-get-reindexer-enable($CONFIG, $db))
  then rx:maybe-disable($db)
  else rx:maybe-enable($db),
  (: Some forests may need merges, to remove deleted fragments :)
  rx:maybe-merge($db),
  rx:debug(
    ('finished: reindex =', admin:database-get-reindexer-enable($CONFIG, $db),
      'merge =', count(xdmp:merging())))
};

(: threx.xqy :)
