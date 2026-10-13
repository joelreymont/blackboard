\ Blackboard CLI port for macOS. FSEvents wakes the descriptor-bound board scan.
require lib/errors.f
require lib/string.f
require lib/fs.f
require lib/fs-mutate.f
require lib/fs-list.f
require lib/date.f
require lib/ffi-abi.f
require lib/ffi-callback.f
require lib/memory.f

package BB

1048576 constant MAX-MSG
1049000 constant CONTENT-CAP

create ROOT-BUF FS-PATH-CAP allot
variable ROOT-U
create CWD-BUF FS-PATH-CAP allot
create CHAN-BUF FS-PATH-CAP allot
variable CHAN-U
create FILE-BUF FS-PATH-CAP allot
variable FILE-U
create TEMP-BUF FS-PATH-CAP allot
variable TEMP-U
create CURSOR-BUF FS-PATH-CAP allot
variable CURSOR-U
DYNAMIC-BUFFER LIST-BUF u8
variable LIST-U
DYNAMIC-BUFFER CHANS-BUF u8
variable CHANS-U
create OUT-EMPTY 1 allot
DYNAMIC-BUFFER OUT-BUF u8
variable OUT-CAP
variable OUT-U
DYNAMIC-BUFFER ERR-BUF u8
variable ERR-U
DYNAMIC-BUFFER CUR-RAW u8
variable CUR-RAW-U
PTR-VARIABLE CUR-PREV-A
variable CUR-PREV-U
DYNAMIC-BUFFER ACK-IDS u8
variable ACK-IDS-U
DYNAMIC-BUFFER ACK-RECS n
variable ACK-COUNT
DYNAMIC-BUFFER PEND-IDS u8
variable PEND-IDS-U
DYNAMIC-BUFFER PEND-RECS n
variable PEND-COUNT
DYNAMIC-BUFFER PEND-CHANS u8
variable PEND-CHANS-U
DYNAMIC-BUFFER PEND-GROUPS n
variable PEND-GROUP-COUNT
create CUR-TEMP-BUF FS-PATH-CAP allot
variable CUR-TEMP-U
create CUR-MAGIC 0 c, 98 c, 98 c, 45 c, 99 c, 117 c, 114 c,
   115 c, 111 c, 114 c, 45 c, 118 c, 50 c, 0 c,
14 constant CUR-MAGIC-U
$100 constant CUR-O-NOFOLLOW
$4 constant CUR-O-NONBLOCK
$800 constant CUR-O-EXCL
$100000 constant CUR-O-DIRECTORY
create CONTENT-BUF CONTENT-CAP allot
variable CONTENT-U
create BODY-BUF MAX-MSG 1+ allot
create ID-BUF 256 allot
variable ID-U
DYNAMIC-BUFFER NAME-BUF u8
variable NAME-U
create AT-BUF 32 allot
variable AT-U
create CUT-BUF 16 allot
variable CUT-U
create CLOCK-SPEC 16 allot
create RAND-BUF 2 allot
create ERROR-LF 10 c,

PTR-VARIABLE CMD-A
variable CMD-U
PTR-VARIABLE ARG-CHAN-A
variable ARG-CHAN-U
PTR-VARIABLE ARG-FROM-A
variable ARG-FROM-U
PTR-VARIABLE ARG-RE-A
variable ARG-RE-U
PTR-VARIABLE ARG-POS-A
variable ARG-POS-U
PTR-VARIABLE ARG-SINCE-A
variable ARG-SINCE-U
variable ARG-N
variable ARG-N-SET
variable ARG-T
variable ARG-ALL
variable ARG-MD
variable ARG-ACK
DYNAMIC-BUFFER NUM-BUF u8
variable NUM-U
variable NUM-NEG

PTR-VARIABLE MSG-FROM-A
variable MSG-FROM-U
PTR-VARIABLE MSG-AT-A
variable MSG-AT-U
PTR-VARIABLE MSG-RE-A
variable MSG-RE-U
PTR-VARIABLE MSG-BODY-A
variable MSG-BODY-U
PTR-VARIABLE MSG-ID-A
variable MSG-ID-U

PTR-VARIABLE ACTIVE-CHAN-A
variable ACTIVE-CHAN-U
PTR-VARIABLE ACTIVE-WHO-A
variable ACTIVE-WHO-U
variable SEEN-N
variable SKIP-N
variable RENDER-N
DYNAMIC-BUFFER LIST-RECS n
DYNAMIC-BUFFER CHANS-RECS n
variable LIST-BYTES
variable CHANS-BYTES
variable SORT-GAP
variable SORT-I
variable SORT-J
create WATCH-PATH-ARRAY CELL allot
create WATCH-CONTEXT 5 cells allot
variable WATCH-CHANNELS-DEV
variable WATCH-CHANNELS-INO
create WATCH-STAT 256 allot
DYNAMIC-BUFFER WATCH-NAMES u8
DYNAMIC-BUFFER WATCH-RECS n
variable WATCH-NAMES-U
variable WATCH-COUNT
DYNAMIC-BUFFER WATCH-FILE-NAMES u8
DYNAMIC-BUFFER WATCH-FILE-RECS n
variable WATCH-FILE-NAMES-U
variable WATCH-FILE-COUNT
variable WATCH-PARENT-DEV
variable WATCH-PARENT-INO
variable WATCH-WAKE
variable WATCH-PATH
variable WATCH-PATHS
variable WATCH-MODE
variable WATCH-STREAM
variable WATCH-DEADLINE
variable WATCH-POLL-DEADLINE

PROCESS-SYMBOLS
FUNCTION: CLOCK-GETTIME-CALL clock_gettime ( n ptr u8 -- i32 )
   1 16 WRITES-BYTES
;FUNCTION
FUNCTION: GETCWD-CALL getcwd ( ptr u8 n -- ptr u8 )
   0 FS-PATH-CAP WRITES-BYTES
;FUNCTION
FUNCTION: EXIT-CALL exit ( n -- ) ;FUNCTION
FUNCTION: CHDIR-CALL chdir ( ptr u8 -- i32 ) ;FUNCTION
FUNCTION: FSTAT-CALL fstat ( n ptr u8 -- i32 )
   1 256 WRITES-BYTES
;FUNCTION
FUNCTION: MKDIR-CALL mkdir ( ptr u8 n -- i32 ) ;FUNCTION
FUNCTION: STAT-CALL stat ( ptr u8 ptr u8 -- i32 )
   1 256 WRITES-BYTES
;FUNCTION
FUNCTION: LSTAT-CALL lstat ( ptr u8 ptr u8 -- i32 )
   1 256 WRITES-BYTES
;FUNCTION
FUNCTION: RENAME-CALL rename ( ptr u8 ptr u8 -- i32 ) ;FUNCTION
FUNCTION: OPEN-CALL open ( ptr u8 n n -- i32 ) 2 VARIADIC ;FUNCTION
FUNCTION: FLOCK-CALL flock ( n n -- i32 ) ;FUNCTION
FUNCTION: CLOSE-CALL close ( n -- i32 ) ;FUNCTION

LIBRARY /System/Library/Frameworks/CoreServices.framework/CoreServices
FUNCTION: CF-STRING-CALL CFStringCreateWithCString ( ptr u8 ptr u8 n -- n ) ;FUNCTION
FUNCTION: CF-ARRAY-CALL CFArrayCreate ( ptr u8 ptr u8 n ptr u8 -- n ) ;FUNCTION
FUNCTION: CF-RELEASE-CALL CFRelease ( n -- ) ;FUNCTION
FUNCTION: CF-LOOP-CALL CFRunLoopGetCurrent ( -- n ) ;FUNCTION
FUNCTION: CF-RUN-CALL CFRunLoopRunInMode ( n r n -- i32 ) ;FUNCTION
FUNCTION: FS-CREATE-CALL FSEventStreamCreate ( ptr u8 n ptr u8 n n r n -- n ) ;FUNCTION
FUNCTION: FS-SCHEDULE-CALL FSEventStreamScheduleWithRunLoop ( n n n -- ) ;FUNCTION
FUNCTION: FS-START-CALL FSEventStreamStart ( n -- i32 ) ;FUNCTION
FUNCTION: FS-STOP-CALL FSEventStreamStop ( n -- ) ;FUNCTION
FUNCTION: FS-INVALIDATE-CALL FSEventStreamInvalidate ( n -- ) ;FUNCTION
FUNCTION: FS-RELEASE-CALL FSEventStreamRelease ( n -- ) ;FUNCTION

CALLBACK: FS-EVENT ( ptr u8 ptr u8 n ptr u8 ptr u8 ptr u8 -- ) ;CALLBACK
CAST: WATCH-EVENT-PTR ( n -- ptr u8 )

: ERR-ADD ( ptr u8 n -- )
   {: src:ptr u:n :}
   ERR-U @ u + ERR-BUF-RESERVE
   src 0 ERR-BUF ERR-U @ + u BYTE-COPY
   u ERR-U +! ;
: ERROR-BEGIN ( -- ) 0 ERR-U ! s" bb: " ERR-ADD ;
: ERROR-NEWLINE ( -- )
   2 ERROR-LF BYTE-VIEW 1 write 1 <> if 1 EXIT-CALL then ;
: ERROR-END ( -- )
   0 begin dup ERR-U @ < while
      {: off:n :}
      2 0 ERR-BUF off + ERR-U @ off - write {: got:n :}
      got 0 <= if 1 EXIT-CALL then
      off got +
   repeat drop
   ERROR-NEWLINE s" " 1 die ;
: FAIL ( ptr u8 n -- )
   {: a:ptr u:n :}
   ERROR-BEGIN a u ERR-ADD ERROR-END ;

: ERROR-LINE ( ptr u8 n -- )
   {: src:ptr size:n :}
   0 begin dup size < while
      {: off:n :}
      2 src off + size off - write {: got:n :}
      got 0 <= if 1 EXIT-CALL then
      off got +
   repeat drop
   ERROR-NEWLINE ;
: STREAM-TOO-LONG ( -- ) s" error: StreamTooLong" ERROR-LINE 1 EXIT-CALL ;
: NOT-DIR ( -- ) s" error: NotDir" ERROR-LINE 1 EXIT-CALL ;
: IS-DIR ( -- ) s" error: IsDir" ERROR-LINE 1 EXIT-CALL ;
: FILE-NOT-FOUND ( -- ) s" error: FileNotFound" ERROR-LINE 1 EXIT-CALL ;
: WRITE-FAILED ( -- ) s" error: WriteFailed" ERROR-LINE 1 EXIT-CALL ;
: NAME-TOO-LONG ( -- ) s" error: NameTooLong" ERROR-LINE 1 EXIT-CALL ;
: ACCESS-DENIED ( -- ) s" error: AccessDenied" ERROR-LINE 1 EXIT-CALL ;
: SYMLINK-LOOP ( -- ) s" error: SymLinkLoop" ERROR-LINE 1 EXIT-CALL ;
: READ-FAILED ( -- ) s" error: ReadFailed" ERROR-LINE 1 EXIT-CALL ;

: FS-ERROR ( n ptr u8 n -- )
   {: code:n fallback:ptr size:n :}
   code 0= if exit then
   FFI:ERRNO {: err:n :}
   err 13 = if ACCESS-DENIED then
   err 20 = if NOT-DIR then
   err 21 = if IS-DIR then
   err 2 = if FILE-NOT-FOUND then
   err 62 = if SYMLINK-LOOP then
   fallback size ERROR-LINE 1 EXIT-CALL ;

: OUT-RESET ( -- ) 0 OUT-U ! ;
: OUT-NEED ( n -- )
   OUT-U @ + {: want:n :}
   OUT-CAP @ 0= if 1024 OUT-CAP ! then
   begin OUT-CAP @ want < while OUT-CAP @ 2 * OUT-CAP ! repeat
   OUT-CAP @ OUT-BUF-RESERVE ;
: OUT-ADD ( ptr u8 n -- )
   {: src:ptr u:n :}
   u OUT-NEED
   src 0 OUT-BUF OUT-U @ + u BYTE-COPY
   u OUT-U +! ;
: OUT-C ( n -- )
   1 OUT-NEED
   0 OUT-BUF OUT-U @ + c! 1 OUT-U +! ;
: OUT-LF ( -- ) 10 OUT-C ;
: OUT-FLUSH ( -- )
   0 begin dup OUT-U @ < while
      {: off:n :}
      1 0 OUT-BUF off + OUT-U @ off - write {: got:n :}
      got 0 <= if WRITE-FAILED then
      off got +
   repeat drop
   OUT-RESET ;

: USAGE ( -- )
   s" bb — blackboard chat for agents and humans" ERROR-LINE
   ERROR-NEWLINE
   s" usage:" ERROR-LINE
   s"   bb init                                   create .blackboard/ in cwd" ERROR-LINE
   s"   bb post [-c chan] [-f who] [--re id] <text|->  post message (- reads stdin)" ERROR-LINE
   s"   bb log [-c chan] [-n N | --all] [--since d] [--md]  transcript (d = today | YYYY-MM-DD, UTC)" ERROR-LINE
   s"   bb unread [-f who] [-c chan] [--ack]      unseen messages from others" ERROR-LINE
   s"   bb ack [-f who] [-c chan]                 mark everything read" ERROR-LINE
   s"   bb watch [-f who] [-c chan] [-t secs]     block until new mail (0 = forever)" ERROR-LINE
   s"   bb channels                               list channels" ERROR-LINE
   ERROR-NEWLINE
   s" identity: -f or $BB_AGENT. root: nearest .blackboard/ upward from cwd, or $BB_ROOT." ERROR-LINE
   s" watch exits 0 when new mail was printed, 2 on timeout." ERROR-LINE ;

: BB-FALSE ( -- bool ) 0 0= 0= ;
: BB-TRUE ( -- bool ) 0 0= ;

: ROOT$ ( -- ptr u8 n ) ROOT-BUF ROOT-U @ ;
: WORK-DIR$ ( -- ptr u8 n )
   CWD-BUF FS-PATH-CAP GETCWD-CALL NULL-PTR = if NAME-TOO-LONG then
   CWD-BUF CWD-BUF ZLEN ;
: CHAN$ ( -- ptr u8 n ) CHAN-BUF CHAN-U @ ;
: FILE$ ( -- ptr u8 n ) FILE-BUF FILE-U @ ;
: TEMP$ ( -- ptr u8 n ) TEMP-BUF TEMP-U @ ;
: CURSOR$ ( -- ptr u8 n ) CURSOR-BUF CURSOR-U @ ;
: BAD-CURSOR ( -- )
   ERROR-BEGIN s" malformed cursor file: " ERR-ADD CURSOR$ ERR-ADD ERROR-END ;
: ID$ ( -- ptr u8 n ) ID-BUF ID-U @ ;
: AT$ ( -- ptr u8 n ) AT-BUF AT-U @ ;

: JOIN-INTO ( ptr u8 n ptr u8 n ptr u8 ptr n -- )
   {: pa:ptr pu:n na:ptr nu:n dst:ptr lenp:ptr :}
   pu nu + 1+ {: joined:n :}
   pu 0 > if pa pu 1- + c@ 47 = if joined 1- else joined then else joined then
   FS-PATH-CAP >= if NAME-TOO-LONG then
   pa pu na nu dst JOIN-PATH lenp ! ;

: COPY-INTO ( ptr u8 n ptr u8 ptr n -- )
   {: src:ptr u:n dst:ptr lenp:ptr :}
   u FS-PATH-CAP >= if NAME-TOO-LONG then
   src dst u BYTE-COPY u lenp ! ;

: VALID-CHAR? ( n -- bool ) {: c:n :}
   c 97 >= c 122 <= and if BB-TRUE exit then
   c 48 >= c 57 <= and if BB-TRUE exit then
   c 45 = c 95 = or c 46 = or ;

: VALID-NAME? ( ptr u8 n -- bool ) {: a:ptr u:n :}
   u 0 <= u 64 > or if BB-FALSE exit then
   a c@ 46 = a c@ 45 = or if BB-FALSE exit then
   u 0 ?do a i + c@ VALID-CHAR? 0= if BB-FALSE unloop exit then loop
   BB-TRUE ;

: BYTE-LESS? ( ptr u8 n ptr u8 n -- bool )
   {: a:ptr u:n b:ptr v:n :}
   u v min 0 ?do
      a i + c@ b i + c@ <> if a i + c@ b i + c@ < unloop exit then
   loop
   u v < ;

: ARG= ( ptr u8 n ptr u8 n -- bool ) STR= ;

: NEED-VALUE ( n -- ptr u8 n )
   dup 1+ script-argc >= if
      ERROR-BEGIN script-argv$ ERR-ADD s"  requires a value" ERR-ADD ERROR-END
   then
   1+ script-argv$ ;

: NORMALIZE-NUMBER ( ptr u8 n -- ptr u8 n bool )
   {: raw:ptr size:n :}
   size 0= if s" " BB-FALSE exit then
   0 NUM-NEG !
   raw c@ 43 = raw c@ 45 = or if
      raw c@ 45 = if 1 NUM-NEG ! then
      1
   else 0 then {: start:n :}
   start size = if s" " BB-FALSE exit then
   size NUM-BUF-RESERVE
   0 NUM-U !
   size start ?do
      raw i + c@ {: c:n :}
      c 95 = if
         i start = i size 1- = or if s" " BB-FALSE unloop exit then
      else
         c 48 < c 57 > or if s" " BB-FALSE unloop exit then
         c NUM-U @ NUM-BUF c!
         1 NUM-U +!
      then
   loop
   0 begin
      dup 1+ NUM-U @ < if dup NUM-BUF c@ 48 = else BB-FALSE then
   while 1+ repeat
   {: skip:n :}
   0 NUM-BUF skip + NUM-U @ skip - {: digits:ptr du:n :}
   NUM-NEG @ 0<> if
      du 1 <> if s" " BB-FALSE exit then
      digits c@ 48 <> if s" " BB-FALSE exit then
   then
   digits du BB-TRUE ;

: DECIMAL-LE? ( ptr u8 n ptr u8 n -- bool )
   {: a:ptr u:n b:ptr v:n :}
   u v < if BB-TRUE exit then
   u v > if BB-FALSE exit then
   a u b v STR= if BB-TRUE exit then
   a u b v BYTE-LESS? ;

: PARSE-UNSIGNED ( ptr u8 n ptr u8 n -- n bool )
   {: raw:ptr rawu:n maxstr:ptr maxu:n :}
   raw rawu NORMALIZE-NUMBER 0= if 2drop 0 BB-FALSE exit then
   {: digits:ptr du:n :}
   digits du maxstr maxu DECIMAL-LE? 0= if 0 BB-FALSE exit then
   digits du s" 9223372036854775807" DECIMAL-LE? 0= if
      9223372036854775807 BB-TRUE exit
   then
   digits du STR>NUMBER? MATCH option
      none OF 0 BB-FALSE ENDOF
      some OF BB-TRUE ENDOF
   ;MATCH ;

: ARG-RESET ( -- )
   NULL-PTR ARG-CHAN-A ! 0 ARG-CHAN-U !
   NULL-PTR ARG-FROM-A ! 0 ARG-FROM-U !
   NULL-PTR ARG-RE-A ! 0 ARG-RE-U !
   NULL-PTR ARG-POS-A ! 0 ARG-POS-U !
   NULL-PTR ARG-SINCE-A ! 0 ARG-SINCE-U !
   20 ARG-N ! 600 ARG-T ! 0 ARG-N-SET ! 0 ARG-ALL ! 0 ARG-MD ! 0 ARG-ACK ! ;

: PARSE-ARG ( n -- n ) {: idx:n :}
   idx script-argv$ {: a:ptr u:n :}
   a u s" -c" ARG= if idx NEED-VALUE ARG-CHAN-U ! ARG-CHAN-A ! idx 1+ exit then
   a u s" -f" ARG= if idx NEED-VALUE ARG-FROM-U ! ARG-FROM-A ! idx 1+ exit then
   a u s" --re" ARG= if idx NEED-VALUE ARG-RE-U ! ARG-RE-A ! idx 1+ exit then
   a u s" --since" ARG= if idx NEED-VALUE ARG-SINCE-U ! ARG-SINCE-A ! idx 1+ exit then
   a u s" -n" ARG= if
      idx NEED-VALUE s" 18446744073709551615" PARSE-UNSIGNED 0= if
         drop ERROR-BEGIN s" -n: not a number: " ERR-ADD idx 1+ script-argv$ ERR-ADD ERROR-END
      then
      ARG-N !
      1 ARG-N-SET ! idx 1+ exit
   then
   a u s" -t" ARG= if
      idx NEED-VALUE s" 4294967295" PARSE-UNSIGNED 0= if
         drop ERROR-BEGIN s" -t: not a number: " ERR-ADD idx 1+ script-argv$ ERR-ADD ERROR-END
      then
      ARG-T !
      idx 1+ exit
   then
   a u s" --all" ARG= if 1 ARG-ALL ! idx exit then
   a u s" --md" ARG= if 1 ARG-MD ! idx exit then
   a u s" --ack" ARG= if 1 ARG-ACK ! idx exit then
   a u s" -h" ARG= a u s" --help" ARG= or if USAGE 0 EXIT-CALL then
   u 1 > if a c@ 45 = if ERROR-BEGIN s" unknown flag: " ERR-ADD a u ERR-ADD ERROR-END then then
   ARG-POS-A @ NULL-PTR <> if s" only one positional argument allowed (quote the message)" FAIL then
   a ARG-POS-A ! u ARG-POS-U ! idx ;

: PARSE-ARGS ( -- )
   ARG-RESET
   script-argc 0= if USAGE 1 EXIT-CALL then
   0 script-argv$ CMD-U ! CMD-A !
   1 begin dup script-argc < while PARSE-ARG 1+ repeat drop ;

: CHAN-ARG$ ( -- ptr u8 n )
   ARG-CHAN-A @ NULL-PTR = if s" general" exit then ARG-CHAN-A @ ARG-CHAN-U @ ;

: IDENTITY$ ( -- ptr u8 n )
   ARG-FROM-A @ NULL-PTR <> if
      ARG-FROM-A @ ARG-FROM-U @ 2dup VALID-NAME? 0= if
         ERROR-BEGIN s" invalid identity: " ERR-ADD 2dup ERR-ADD
         s"  (allowed [a-z0-9._-], no leading . or -)" ERR-ADD ERROR-END
      then exit
   then
   s" BB_AGENT" GETENV over NULL-PTR = if 2drop s" identity unknown: pass -f <name> or set $BB_AGENT" FAIL then
   2dup VALID-NAME? 0= if
      ERROR-BEGIN s" invalid identity: " ERR-ADD 2dup ERR-ADD
      s"  (allowed [a-z0-9._-], no leading . or -)" ERR-ADD ERROR-END
   then ;

: ROOT-READY ( -- )
   s" ." FS-PATHZ 0 0 OPEN-CALL {: fd:n :}
   fd 0 < if
      FFI:ERRNO {: err:n :}
      err 13 = if ACCESS-DENIED then
      err 62 = if SYMLINK-LOOP then
      E-FS-OPEN throw
   then
   fd close
   s" ." ROOT-BUF ROOT-U COPY-INTO ;

: ENTER-BOARD? ( -- bool )
   s" .blackboard" FS-PATHZ CHDIR-CALL 0= if ROOT-READY BB-TRUE exit then
   FFI:ERRNO {: err:n :}
   err 20 = if NOT-DIR then
   err 13 = if ACCESS-DENIED then
   err 62 = if SYMLINK-LOOP then
   err 2 <> if s" error: FileNotFound" ERROR-LINE 1 EXIT-CALL then
   BB-FALSE ;

: ROOT-MISSING ( ptr u8 n -- )
   {: path:ptr size:n :}
   ERROR-BEGIN s" no .blackboard/ at " ERR-ADD path size ERR-ADD
   size 0 > if path size 1- + c@ 47 <> if s" /" ERR-ADD then then
   s" .blackboard (run `bb init`)" ERR-ADD ERROR-END ;

: MKDIR-ONE-CHECKED ( ptr u8 n -- )
   {: path:ptr size:n :}
   path size FS-PATHZ 493 MKDIR-CALL 0= if exit then
   FFI:ERRNO {: err:n :}
   err 17 = if
      path size FS-PATHZ WATCH-STAT LSTAT-CALL 0= if
         WATCH-STAT 4 + FS-U16@ S-IFMT and S-IFDIR = if exit then
      else
         FFI:ERRNO 13 = if ACCESS-DENIED then
      then
      NOT-DIR
   then
   err 20 = if NOT-DIR then
   err 13 = if ACCESS-DENIED then
   E-FS-IO throw ;

: MAKE-DIRS-CHECKED ( ptr u8 n -- )
   {: path:ptr size:n :}
   1 begin dup size < while
      path over + c@ 47 = if
         path over MKDIR-ONE-CHECKED
      then
      1+
   repeat drop
   path size MKDIR-ONE-CHECKED ;

: DIR-STATE ( ptr u8 n -- bool )
   {: path:ptr size:n :}
   path size FS-PATHZ WATCH-STAT STAT-CALL 0= if
      WATCH-STAT 4 + FS-U16@ S-IFMT and S-IFDIR = if BB-TRUE exit then
      NOT-DIR
   then
   FFI:ERRNO {: err:n :}
   err 2 = if BB-FALSE exit then
   err 20 = if NOT-DIR then
   err 13 = if ACCESS-DENIED then
   err 62 = if SYMLINK-LOOP then
   E-FS-STAT throw ;

: OPEN-ROOT ( -- )
   s" BB_ROOT" GETENV over NULL-PTR <> if
      {: path:ptr size:n :}
      size 0 > if path size FS-PATHZ CHDIR-CALL 0<> if
         FFI:ERRNO {: err:n :}
         err 20 = if NOT-DIR then
         err 13 = if ACCESS-DENIED then
         err 62 = if SYMLINK-LOOP then
         path size ROOT-MISSING
      then then
      ENTER-BOARD? 0= if path size ROOT-MISSING then exit
   then 2drop
   begin
      WORK-DIR$ nip 12 + FS-PATH-CAP >= if NAME-TOO-LONG then
      ENTER-BOARD? if exit then
      WORK-DIR$ nip 1 = if
         s" no .blackboard/ found upward from cwd (run `bb init` at the project root)" FAIL
      then
      s" .." FS-PATHZ CHDIR-CALL 0<> if NOT-DIR then
   again ;

: MAKE-CHAN-PATH ( ptr u8 n -- )
   ROOT$ s" channels" CHAN-BUF CHAN-U JOIN-INTO
   CHAN$ 2swap CHAN-BUF CHAN-U JOIN-INTO ;

: MAKE-FILE-PATH ( ptr u8 n -- )
   CHAN$ 2swap FILE-BUF FILE-U JOIN-INTO ;

: MAKE-CURSOR-PATH ( ptr u8 n ptr u8 n -- )
   {: who:ptr whou:n chan:ptr chanu:n :}
   ROOT$ s" cursors" CURSOR-BUF CURSOR-U JOIN-INTO
   CURSOR$ who whou CURSOR-BUF CURSOR-U JOIN-INTO
   CURSOR$ chan chanu CURSOR-BUF CURSOR-U JOIN-INTO ;

: MAKE-CURSOR-DIR ( ptr u8 n -- )
   ROOT$ s" cursors" CURSOR-BUF CURSOR-U JOIN-INTO
   CURSOR$ 2swap CURSOR-BUF CURSOR-U JOIN-INTO
   CURSOR$ MAKE-DIRS-CHECKED ;

: INIT ( -- )
   s" .blackboard/channels/general" MAKE-DIRS-CHECKED
   s" .blackboard/cursors" MAKE-DIRS-CHECKED
   s" .blackboard/tmp" MAKE-DIRS-CHECKED
   OUT-RESET s" initialized " OUT-ADD WORK-DIR$ OUT-ADD
   s" /.blackboard" OUT-ADD OUT-LF OUT-FLUSH ;

: NOW-MS ( -- n )
   0 CLOCK-SPEC BYTE-VIEW CLOCK-GETTIME-CALL 0<> if s" clock failed" FAIL then
   CLOCK-SPEC @ 1000 * CLOCK-SPEC cell+ @ 1000000 / + ;

: RANDOM-U16 ( -- n )
   s" /dev/urandom" FS-PATHZ open-rd {: fd:n :}
   fd 0 < if s" cannot open /dev/urandom" FAIL then
   fd RAND-BUF BYTE-VIEW 2 read {: got:n :}
   fd close
   got 2 <> if s" cannot read /dev/urandom" FAIL then
   RAND-BUF BYTE-VIEW c@ RAND-BUF BYTE-VIEW 1+ c@ 8 lshift or ;

: HEX-CHAR ( n -- n )
   dup 10 < if 48 + else 10 - 97 + then ;

: FORMAT-STAMP ( n -- ) {: ms:n :}
   ms 1000 / AT-BUF 32 DATE:FORMAT-EPOCH-UTC 2drop
   46 AT-BUF 19 + c!
   ms 1000 mod 3 AT-BUF 20 DATE:WIDTH!
   90 AT-BUF 23 + c!
   24 AT-U ! ;

: FORMAT-ID ( ptr u8 n n -- ) {: from:ptr fromu:n rand:n :}
   AT-BUF 0 + ID-BUF 0 + 4 BYTE-COPY
   AT-BUF 5 + ID-BUF 4 + 2 BYTE-COPY
   AT-BUF 8 + ID-BUF 6 + 2 BYTE-COPY
   45 ID-BUF 8 + c!
   AT-BUF 11 + ID-BUF 9 + 2 BYTE-COPY
   AT-BUF 14 + ID-BUF 11 + 2 BYTE-COPY
   AT-BUF 17 + ID-BUF 13 + 2 BYTE-COPY
   46 ID-BUF 15 + c!
   AT-BUF 20 + ID-BUF 16 + 3 BYTE-COPY
   45 ID-BUF 19 + c!
   from ID-BUF 20 + fromu BYTE-COPY
   45 ID-BUF 20 fromu + + c!
   4 0 ?do
      rand 12 i 4 * - rshift 15 and HEX-CHAR ID-BUF 21 fromu + i + + c!
   loop
   25 fromu + ID-U ! ;

: MAKE-NAME ( ptr u8 n -- ptr u8 n ) {: id:ptr u:n :}
   u 3 + NAME-BUF-RESERVE
   id 0 NAME-BUF u BYTE-COPY
   46 0 NAME-BUF u + c! 109 0 NAME-BUF u 1+ + c! 100 0 NAME-BUF u 2 + + c!
   u 3 + NAME-U ! 0 NAME-BUF NAME-U @ ;

: CONTENT-RESET ( -- ) 0 CONTENT-U ! ;
: CONTENT-ADD ( ptr u8 n -- ) {: a:ptr u:n :}
   CONTENT-U @ u + CONTENT-CAP > if s" message exceeds 1048576 bytes" FAIL then
   a CONTENT-BUF CONTENT-U @ + u BYTE-COPY
   u CONTENT-U +! ;
: CONTENT-C ( n -- ) {: c:n :}
   CONTENT-U @ CONTENT-CAP >= if s" message exceeds 1048576 bytes" FAIL then
   c CONTENT-BUF CONTENT-U @ + c! 1 CONTENT-U +! ;

: READ-STDIN ( -- ptr u8 n )
   0 begin dup MAX-MSG < while
      dup {: off:n :}
      0 BODY-BUF off + MAX-MSG off - read {: got:n :}
      got 0 < if s" stdin read failed" FAIL then
      got 0= if BODY-BUF swap exit then
      got +
   repeat
   0 BODY-BUF MAX-MSG + 1 read {: extra:n :}
   extra 0 < if READ-FAILED then
   extra 0 > if s" message exceeds 1048576 bytes" FAIL then
   BODY-BUF swap ;

: POST-RAW-BODY$ ( -- ptr u8 n )
   ARG-POS-A @ NULL-PTR = if s" post: message text required (or - for stdin)" FAIL then
   ARG-POS-A @ ARG-POS-U @ s" -" STR= if READ-STDIN else ARG-POS-A @ ARG-POS-U @ then
   ;

: POST-CONTENT ( ptr u8 n ptr u8 n -- )
   {: from:ptr fromu:n body:ptr bodyu:n :}
   CONTENT-RESET
   s" ---" CONTENT-ADD 10 CONTENT-C
   s" from: " CONTENT-ADD from fromu CONTENT-ADD 10 CONTENT-C
   s" at: " CONTENT-ADD AT$ CONTENT-ADD
   ARG-RE-A @ NULL-PTR <> if
      10 CONTENT-C s" re: " CONTENT-ADD ARG-RE-A @ ARG-RE-U @ CONTENT-ADD
   then
   10 CONTENT-C s" ---" CONTENT-ADD 10 CONTENT-C 10 CONTENT-C
   body bodyu CONTENT-ADD 10 CONTENT-C ;

: POST-WRITE ( -- )
   TEMP$ FS-PATHZ FS-O-WRONLY FS-O-CREAT or FS-O-TRUNC or
   FS-MODE-0644 OPEN-CALL {: fd:n :}
   fd 0 < if 1 s" error: WriteFailed" FS-ERROR then
   0 begin dup CONTENT-U @ < while
      {: off:n :}
      fd CONTENT-BUF off + CONTENT-U @ off - write {: got:n :}
      got 0 <= if fd close WRITE-FAILED then
      off got +
   repeat drop
   fd CLOSE-CALL 0<> if WRITE-FAILED then ;

: POST-RENAME ( -- )
   0 FILE-BUF FILE-U @ + c!
   TEMP$ FS-PATHZ FILE-BUF RENAME-CALL 0<> if
      1 s" error: RenameFailed" FS-ERROR
   then ;

: POST ( -- )
   IDENTITY$ {: from:ptr fromu:n :}
   CHAN-ARG$ {: chan:ptr chanu:n :}
   chan chanu VALID-NAME? 0= if
      ERROR-BEGIN s" invalid channel: " ERR-ADD chan chanu ERR-ADD ERROR-END
   then
   POST-RAW-BODY$ {: raw:ptr rawu:n :}
   ARG-RE-A @ NULL-PTR <> if
      ARG-RE-A @ ARG-RE-U @ VALID-NAME? 0= if
         ERROR-BEGIN s" invalid name in chan=" ERR-ADD chan chanu ERR-ADD
         s"  from=" ERR-ADD from fromu ERR-ADD
         s"  re=" ERR-ADD ARG-RE-A @ ARG-RE-U @ ERR-ADD ERROR-END
      then
   then
   raw rawu TRIM {: body:ptr bodyu:n :}
   bodyu 0= if s" empty message" FAIL then
   bodyu MAX-MSG > if s" message exceeds 1048576 bytes" FAIL then
   NOW-MS FORMAT-STAMP
   from fromu RANDOM-U16 FORMAT-ID
   from fromu body bodyu POST-CONTENT
   chan chanu MAKE-CHAN-PATH CHAN$ MAKE-DIRS-CHECKED
   ID$ MAKE-NAME {: name:ptr nameu:n :}
   CHAN$ name nameu FILE-BUF FILE-U JOIN-INTO
   ROOT$ s" tmp" TEMP-BUF TEMP-U JOIN-INTO
   TEMP$ MAKE-DIRS-CHECKED
   TEMP$ name nameu TEMP-BUF TEMP-U JOIN-INTO
   POST-WRITE
   POST-RENAME
   OUT-RESET ID$ OUT-ADD OUT-LF OUT-FLUSH ;

: REC$ ( ptr u8 ptr n n -- ptr u8 n )
   {: base:ptr meta:ptr idx:n :}
   meta idx 2 * cells + {: slot:ptr :}
   base slot @ + slot cell+ @ ;

: SWAP-RECS ( ptr n n n -- )
   {: meta:ptr left:n right:n :}
   meta left 2 * cells + {: a:ptr :}
   meta right 2 * cells + {: b:ptr :}
   a @ {: off:n :} a cell+ @ {: size:n :}
   b @ a ! b cell+ @ a cell+ !
   off b ! size b cell+ ! ;

: SORT-RECS ( ptr u8 ptr n n -- )
   {: base:ptr meta:ptr count:n :}
   count 2 / SORT-GAP !
   begin SORT-GAP @ 0 > while
      SORT-GAP @ SORT-I !
      begin SORT-I @ count < while
         SORT-I @ SORT-J !
         begin SORT-J @ SORT-GAP @ >= while
            base meta SORT-J @ REC$
            base meta SORT-J @ SORT-GAP @ - REC$
            BYTE-LESS? if
               meta SORT-J @ SORT-GAP @ - SORT-J @ SWAP-RECS
               SORT-J @ SORT-GAP @ - SORT-J !
            else
               0 SORT-J !
            then
         repeat
         1 SORT-I +!
      repeat
      SORT-GAP @ 2 / SORT-GAP !
   repeat ;

: EACH-REC ( ptr u8 ptr n n [ ptr u8 n -- ] -- )
   {: base:ptr meta:ptr count:n q :}
   count 0 ?do base meta i REC$ q execute loop ;

: CHANNELS-PATH ( -- )
   ROOT$ s" channels" CHAN-BUF CHAN-U JOIN-INTO ;

: ADD-CHANNEL-NAME ( ptr u8 n -- )
   {: name:ptr u:n :}
   CHANS-BYTES @ u + CHANS-BUF-RESERVE
   name 0 CHANS-BUF CHANS-BYTES @ + u BYTE-COPY
   CHANS-U @ 1+ 2 * CHANS-RECS-RESERVE
   CHANS-BYTES @ CHANS-U @ 2 * CHANS-RECS !
   u CHANS-U @ 2 * 1+ CHANS-RECS !
   u CHANS-BYTES +!
   1 CHANS-U +! ;

: CHANNELS-LIST ( -- )
   CHANNELS-PATH
   0 CHANS-U ! 0 CHANS-BYTES !
   1 CHANS-BUF-RESERVE
   1 CHANS-RECS-RESERVE
   CHAN$ DIR-STATE 0= if FILE-NOT-FOUND then
   CHAN$ FS-PATHZ CUR-O-DIRECTORY 0 OPEN-CALL {: fd:n :}
   fd 0 < if 1 s" error: ReadFailed" FS-ERROR then
   fd close
   [: CHAN$ [: ADD-CHANNEL-NAME ;] FS-LIST:EACH ;] catch
   0<> if READ-FAILED then
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ SORT-RECS ;

: PATH-KIND ( ptr u8 n -- n )
   {: path:ptr size:n :}
   path size FS-PATHZ WATCH-STAT LSTAT-CALL 0= if
      WATCH-STAT 4 + FS-U16@ S-IFMT and exit
   then
   FFI:ERRNO {: err:n :}
   err 2 = if 0 exit then
   err 13 = if ACCESS-DENIED then
   err 20 = if NOT-DIR then
   err 62 = if SYMLINK-LOOP then
   s" error: StatFailed" ERROR-LINE 1 EXIT-CALL 0 ;

: MSG-ENTRY? ( ptr u8 n -- bool )
   {: name:ptr nameu:n :}
   nameu 3 < if BB-FALSE exit then
   name nameu s" .md" ENDS-WITH? 0= if BB-FALSE exit then
   CHAN$ name nameu FILE-BUF FILE-U JOIN-INTO
   FILE$ PATH-KIND S-IFREG = ;

: ADD-MESSAGE-NAME ( ptr u8 n -- )
   {: name:ptr u:n :}
   name u MSG-ENTRY? 0= if exit then
   u 3 - {: idu:n :}
   LIST-BYTES @ idu + LIST-BUF-RESERVE
   name 0 LIST-BUF LIST-BYTES @ + idu BYTE-COPY
   LIST-U @ 1+ 2 * LIST-RECS-RESERVE
   LIST-BYTES @ LIST-U @ 2 * LIST-RECS !
   idu LIST-U @ 2 * 1+ LIST-RECS !
   idu LIST-BYTES +!
   1 LIST-U +! ;

: LIST-MESSAGES ( -- )
   s" ./channels" DIR-STATE 0= if
      ERROR-BEGIN s" no such channel: " ERR-ADD
      ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ ERR-ADD ERROR-END
   then
   ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ MAKE-CHAN-PATH
   CHAN$ DIR-STATE 0= if
      ERROR-BEGIN s" no such channel: " ERR-ADD
      ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ ERR-ADD ERROR-END
   then
   0 LIST-U ! 0 LIST-BYTES !
   1 LIST-BUF-RESERVE
   1 LIST-RECS-RESERVE
   CHAN$ FS-PATHZ CUR-O-DIRECTORY 0 OPEN-CALL {: fd:n :}
   fd 0 < if 1 s" error: ReadFailed" FS-ERROR then
   fd close
   [: CHAN$ [: ADD-MESSAGE-NAME ;] FS-LIST:EACH ;] catch
   0<> if READ-FAILED then
   0 LIST-BUF 0 LIST-RECS LIST-U @ SORT-RECS ;

: SET-ACTIVE-CHAN ( ptr u8 n -- )
   ACTIVE-CHAN-U ! ACTIVE-CHAN-A ! ;

: MALFORMED ( -- )
   ERROR-BEGIN s" malformed message file: channels/" ERR-ADD
   ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ ERR-ADD
   s" /" ERR-ADD MSG-ID-A @ MSG-ID-U @ ERR-ADD
   s" .md" ERR-ADD ERROR-END ;

: LINE-FIELD ( ptr u8 n -- ) {: line:ptr lu:n :}
   line lu s" from: " STARTS-WITH? if
      line 6 + MSG-FROM-A ! lu 6 - MSG-FROM-U ! exit
   then
   line lu s" at: " STARTS-WITH? if
      line 4 + MSG-AT-A ! lu 4 - MSG-AT-U ! exit
   then
   line lu s" re: " STARTS-WITH? if
      line 4 + MSG-RE-A ! lu 4 - MSG-RE-U ! exit
   then
   MALFORMED ;

: TRIM-END-LF ( ptr u8 n -- n ) {: a:ptr u:n :}
   u begin dup 0 > while
      dup 1- a + c@ 10 = if 1- else exit then
   repeat ;

: PARSE-MESSAGE ( ptr u8 n -- ) {: data:ptr size:n :}
   NULL-PTR MSG-FROM-A ! 0 MSG-FROM-U !
   NULL-PTR MSG-AT-A ! 0 MSG-AT-U !
   NULL-PTR MSG-RE-A ! 0 MSG-RE-U !
   data size 10 0 SPLIT-NEXT drop {: first:ptr firstu:n off:n :}
   first firstu s" ---" STR= 0= if MALFORMED then
   off size > if MALFORMED then
   off begin dup size <= while
      {: pos:n :}
      data size 10 pos SPLIT-NEXT {: line:ptr lu:n next:n has:bool :}
      has 0= if MALFORMED then
      line lu s" ---" STR= if
         next size > if MALFORMED then
         next size < if data next + c@ 10 = if next 1+ else next then else next then
         {: bodyoff:n :}
         data bodyoff + MSG-BODY-A !
         data bodyoff + size bodyoff - TRIM-END-LF MSG-BODY-U !
         MSG-FROM-A @ NULL-PTR = MSG-AT-A @ NULL-PTR = or if MALFORMED then
         exit
      then
      line lu LINE-FIELD
      next
   repeat drop
   MALFORMED ;

: READ-MESSAGE ( ptr u8 n -- ) {: id:ptr idu:n :}
   id MSG-ID-A ! idu MSG-ID-U !
   id idu MAKE-NAME {: name:ptr nameu:n :}
   CHAN$ name nameu FILE-BUF FILE-U JOIN-INTO
   FILE$ FS-PATHZ 0 0 OPEN-CALL {: fd:n :}
   fd 0 < if 1 s" error: ReadFailed" FS-ERROR then
   fd WATCH-STAT FSTAT-CALL 0<> if fd close READ-FAILED then
   WATCH-STAT 4 + FS-U16@ S-IFMT and S-IFDIR = if fd close IS-DIR then
   0 CONTENT-U !
   begin CONTENT-U @ CONTENT-CAP 1- < while
      fd CONTENT-BUF CONTENT-U @ + CONTENT-CAP 1- CONTENT-U @ - read {: got:n :}
      got 0 < if fd close READ-FAILED then
      got 0= if fd close CONTENT-BUF CONTENT-U @ PARSE-MESSAGE exit then
      got CONTENT-U +!
   repeat
   fd BODY-BUF 1 read {: extra:n :}
   fd close
   extra 0 < if READ-FAILED then
   extra 0 > if STREAM-TOO-LONG then
   CONTENT-BUF CONTENT-U @ PARSE-MESSAGE ;

: RENDER-PLAIN ( -- )
   s" ── " OUT-ADD MSG-FROM-A @ MSG-FROM-U @ OUT-ADD
   s"   #" OUT-ADD ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ OUT-ADD
   s"   " OUT-ADD MSG-AT-A @ MSG-AT-U @ OUT-ADD
   s"   id:" OUT-ADD MSG-ID-A @ MSG-ID-U @ OUT-ADD OUT-LF
   MSG-RE-A @ NULL-PTR <> if
      s"    re:" OUT-ADD MSG-RE-A @ MSG-RE-U @ OUT-ADD OUT-LF
   then
   MSG-BODY-A @ MSG-BODY-U @ OUT-ADD OUT-LF OUT-LF ;

: RENDER-MD ( -- )
   RENDER-N @ 0 > if OUT-LF s" ---" OUT-ADD OUT-LF then
   OUT-LF s" ### " OUT-ADD MSG-FROM-A @ MSG-FROM-U @ OUT-ADD
   s"  — " OUT-ADD MSG-AT-A @ MSG-AT-U @ OUT-ADD OUT-LF
   96 OUT-C MSG-ID-A @ MSG-ID-U @ OUT-ADD 96 OUT-C
   MSG-RE-A @ NULL-PTR <> if
      s"  · re " OUT-ADD 96 OUT-C MSG-RE-A @ MSG-RE-U @ OUT-ADD 96 OUT-C
   then
   OUT-LF OUT-LF MSG-BODY-A @ MSG-BODY-U @ OUT-ADD OUT-LF
   1 RENDER-N +! ;

: RENDER-MESSAGE ( -- )
   ARG-MD @ 0<> if RENDER-MD else RENDER-PLAIN then ;

: CUT-FROM-DATE ( ptr u8 n -- ) {: date:ptr u:n :}
   date 0 + CUT-BUF 0 + 4 BYTE-COPY
   date 5 + CUT-BUF 4 + 2 BYTE-COPY
   date 8 + CUT-BUF 6 + 2 BYTE-COPY
   45 CUT-BUF 8 + c! 9 CUT-U ! ;

: VALID-CUTOFF? ( ptr u8 n -- bool ) {: a:ptr u:n :}
   u 10 <> if BB-FALSE exit then
   a 4 + c@ 45 <> a 7 + c@ 45 <> or if BB-FALSE exit then
   10 0 ?do
      i 4 <> i 7 <> and if
         a i + c@ DATE:DIGIT? 0= if BB-FALSE unloop exit then
      then
   loop
   a 5 + c@ 48 - 10 * a 6 + c@ 48 - + {: month:n :}
   a 8 + c@ 48 - 10 * a 9 + c@ 48 - + {: day:n :}
   month 1 >= month 12 <= and day 1 >= and day 31 <= and ;

: PREPARE-CUT ( -- )
   0 CUT-U !
   ARG-SINCE-A @ NULL-PTR = if exit then
   ARG-SINCE-A @ ARG-SINCE-U @ s" today" STR= if
      NOW-MS 1000 / DATE:SECONDS-DAY / AT-BUF 32 DATE:FORMAT-YMD 2drop
      AT-BUF 10 CUT-FROM-DATE exit
   then
   ARG-SINCE-A @ ARG-SINCE-U @ VALID-CUTOFF? 0= if
      ERROR-BEGIN s" --since: want today or YYYY-MM-DD (UTC): " ERR-ADD
      ARG-SINCE-A @ ARG-SINCE-U @ ERR-ADD ERROR-END
   then
   ARG-SINCE-A @ ARG-SINCE-U @ CUT-FROM-DATE ;

: AFTER-CUT? ( ptr u8 n -- bool )
   CUT-U @ 0= if 2drop BB-TRUE exit then
   CUT-BUF CUT-U @ BYTE-LESS? 0= ;

: COUNT-LOG-ENTRY ( ptr u8 n -- ) {: name:ptr nameu:n :}
   name nameu AFTER-CUT? if 1 SEEN-N +! then ;

: RENDER-LOG-ENTRY ( ptr u8 n -- ) {: name:ptr nameu:n :}
   name nameu AFTER-CUT? 0= if exit then
   SKIP-N @ 0 > if -1 SKIP-N +! exit then
   name nameu READ-MESSAGE RENDER-MESSAGE ;

: LOG ( -- )
   CHAN-ARG$ SET-ACTIVE-CHAN
   LIST-MESSAGES PREPARE-CUT
   0 SEEN-N ! 0 RENDER-N !
   0 LIST-BUF 0 LIST-RECS LIST-U @ [: COUNT-LOG-ENTRY ;] EACH-REC
   ARG-ALL @ 0<> ARG-SINCE-A @ NULL-PTR <> ARG-N-SET @ 0= and or if
      0 SKIP-N !
   else
      SEEN-N @ ARG-N @ - 0 max SKIP-N !
   then
   OUT-RESET
   ARG-MD @ 0<> if s" # #" OUT-ADD ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ OUT-ADD OUT-LF then
   0 LIST-BUF 0 LIST-RECS LIST-U @ [: RENDER-LOG-ENTRY ;] EACH-REC
   OUT-FLUSH ;

: PRINT-CHANNEL ( ptr u8 n -- ) {: name:ptr nameu:n :}
   ROOT$ s" channels" CHAN-BUF CHAN-U JOIN-INTO
   CHAN$ name nameu FILE-BUF FILE-U JOIN-INTO
   FILE$ PATH-KIND S-IFDIR = if name nameu OUT-ADD OUT-LF then ;

: CHANNELS ( -- )
   CHANNELS-LIST
   OUT-RESET
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ [: PRINT-CHANNEL ;] EACH-REC
   OUT-FLUSH ;

: CUR-TEMP$ ( -- ptr u8 n ) CUR-TEMP-BUF CUR-TEMP-U @ ;

: CUR-V2? ( -- bool )
   CUR-RAW-U @ 0 > if 0 CUR-RAW c@ 0= else BB-FALSE then ;

: CUR-ID$ ( n -- ptr u8 n n )
   {: off:n :}
   off begin dup CUR-RAW-U @ < while
      0 CUR-RAW over + c@ 0= if
         {: stop:n :}
         0 CUR-RAW off + stop off - stop 1+ exit
      then
      1+
   repeat
   BAD-CURSOR ;

: CHECK-CURSOR ( -- )
   CUR-V2? if
      CUR-RAW-U @ CUR-MAGIC-U < if BAD-CURSOR then
      0 CUR-RAW CUR-MAGIC-U CUR-MAGIC CUR-MAGIC-U STR= 0= if BAD-CURSOR then
      NULL-PTR CUR-PREV-A ! 0 CUR-PREV-U !
      CUR-MAGIC-U begin dup CUR-RAW-U @ < while
         CUR-ID$ {: id:ptr idu:n next:n :}
         CUR-PREV-A @ NULL-PTR <> if
            CUR-PREV-A @ CUR-PREV-U @ id idu BYTE-LESS? 0= if BAD-CURSOR then
         then
         id CUR-PREV-A ! idu CUR-PREV-U !
         next
      repeat drop
   else
      CUR-RAW-U @ 256 >= if STREAM-TOO-LONG then
      CUR-RAW-U @ 0 ?do
         0 CUR-RAW i + c@ 0= if BAD-CURSOR then
      loop
   then ;

: READ-CURSOR ( -- )
   0 CUR-RAW-U !
   ACTIVE-WHO-A @ ACTIVE-WHO-U @ ACTIVE-CHAN-A @ ACTIVE-CHAN-U @ MAKE-CURSOR-PATH
   CURSOR$ FS-PATHZ CUR-O-NOFOLLOW CUR-O-NONBLOCK or 0 OPEN-CALL {: fd:n :}
   fd 0 < if
      FFI:ERRNO {: err:n :}
      err 2 = if exit then
      err 13 = if ACCESS-DENIED then
      err 20 = if NOT-DIR then
      err 62 = if SYMLINK-LOOP then
      s" error: ReadFailed" ERROR-LINE 1 EXIT-CALL
   then
   fd WATCH-STAT FSTAT-CALL 0<> if fd close READ-FAILED then
   WATCH-STAT 4 + FS-U16@ S-IFMT and S-IFDIR = if fd close IS-DIR then
   WATCH-STAT 4 + FS-U16@ S-IFMT and S-IFREG <> if fd close BAD-CURSOR then
   begin
      CUR-RAW-U @ 4096 + CUR-RAW-RESERVE
      fd 0 CUR-RAW CUR-RAW-U @ + 4096 read {: got:n :}
      got 0 < if fd close READ-FAILED then
      got 0= if fd close CHECK-CURSOR exit then
      got CUR-RAW-U +!
   again ;

: CUR-MEMBER? ( ptr u8 n -- bool )
   {: id:ptr idu:n :}
   CUR-V2? if
      CUR-MAGIC-U begin dup CUR-RAW-U @ < while
         CUR-ID$ {: cur:ptr size:n next:n :}
         id idu cur size STR= if BB-TRUE exit then
         next
      repeat drop BB-FALSE exit
   then
   CUR-RAW-U @ 0= if BB-FALSE exit then
   0 CUR-RAW {: data:ptr :}
   id idu data data CUR-RAW-U @ TRIM-END-LF STR= ;

: ACK-REC$ ( n -- ptr u8 n )
   0 ACK-IDS 0 ACK-RECS rot REC$ ;

: ACK-MEMBER? ( ptr u8 n -- bool )
   {: id:ptr idu:n :}
   ACK-COUNT @ 0 ?do
      i ACK-REC$ id idu STR= if BB-TRUE unloop exit then
   loop BB-FALSE ;

: ACK-ADD ( ptr u8 n -- )
   {: id:ptr idu:n :}
   id idu ACK-MEMBER? if exit then
   ACK-IDS-U @ idu + ACK-IDS-RESERVE
   id 0 ACK-IDS ACK-IDS-U @ + idu BYTE-COPY
   ACK-COUNT @ 1+ 2 * ACK-RECS-RESERVE
   ACK-IDS-U @ ACK-COUNT @ 2 * ACK-RECS !
   idu ACK-COUNT @ 2 * 1+ ACK-RECS !
   idu ACK-IDS-U +! 1 ACK-COUNT +! ;

: ACK-OLD ( -- )
   CUR-V2? if
      CUR-MAGIC-U begin dup CUR-RAW-U @ < while
         CUR-ID$ {: cur:ptr size:n next:n :}
         cur size ACK-ADD
         next
      repeat drop exit
   then
   CUR-RAW-U @ 0 > if
      0 CUR-RAW {: data:ptr :}
      data data CUR-RAW-U @ TRIM-END-LF ACK-ADD
   then ;

: CUR-TEMP-NAME ( -- )
   CURSOR$ drop CURSOR-U @ ACTIVE-CHAN-U @ - CUR-TEMP-BUF CUR-TEMP-U COPY-INTO
   CUR-TEMP-U @ 9 + FS-PATH-CAP >= if NAME-TOO-LONG then
   s" .tmp-" drop CUR-TEMP-BUF CUR-TEMP-U @ + 5 BYTE-COPY
   5 CUR-TEMP-U +!
   RANDOM-U16 {: rand:n :}
   4 0 ?do
      rand 12 i 4 * - rshift 15 and HEX-CHAR
      CUR-TEMP-BUF CUR-TEMP-U @ i + + c!
   loop
   4 CUR-TEMP-U +! ;

: CUR-TEMP-OPEN ( -- n )
   64 0 ?do
      CUR-TEMP-NAME
      CUR-TEMP$ FS-PATHZ
      FS-O-WRONLY FS-O-CREAT or CUR-O-EXCL or CUR-O-NOFOLLOW or
      FS-MODE-0644 OPEN-CALL {: fd:n :}
      fd 0 >= if fd unloop exit then
      FFI:ERRNO 17 <> if
         1 s" error: WriteFailed" FS-ERROR
      then
   loop
   WRITE-FAILED -1 ;

: CUR-WRITE ( n ptr u8 n -- )
   {: fd:n data:ptr size:n :}
   0 begin dup size < while
      {: off:n :}
      fd data off + size off - write {: got:n :}
      got 0 <= if
         fd close CUR-TEMP$ FS-PATHZ unlink drop WRITE-FAILED
      then
      off got +
   repeat drop ;

: WRITE-CURSOR ( ptr u8 ptr n n -- )
   {: ids:ptr recs:ptr count:n :}
   count 0= if exit then
   ACTIVE-WHO-A @ ACTIVE-WHO-U @ MAKE-CURSOR-DIR
   CURSOR$ FS-PATHZ CUR-O-NOFOLLOW CUR-O-DIRECTORY or 0 OPEN-CALL {: lockfd:n :}
   lockfd 0 < if 1 s" error: OpenFailed" FS-ERROR then
   lockfd 2 FLOCK-CALL 0<> if lockfd close 1 s" error: LockFailed" FS-ERROR then
   READ-CURSOR
   0 ACK-COUNT ! 0 ACK-IDS-U !
   1 ACK-IDS-RESERVE
   ACK-OLD
   ids recs count [: ACK-ADD ;] EACH-REC
   0 ACK-IDS 0 ACK-RECS ACK-COUNT @ SORT-RECS
   CUR-TEMP-OPEN {: fd:n :}
   fd CUR-MAGIC CUR-MAGIC-U CUR-WRITE
   ACK-COUNT @ 0 ?do
      fd i ACK-REC$ CUR-WRITE
      fd CUR-MAGIC 1 CUR-WRITE
   loop
   fd CLOSE-CALL 0<> if CUR-TEMP$ FS-PATHZ unlink drop WRITE-FAILED then
   0 CURSOR-BUF CURSOR-U @ + c!
   CUR-TEMP$ FS-PATHZ CURSOR-BUF RENAME-CALL 0<> if
      FFI:ERRNO {: err:n :}
      CUR-TEMP$ FS-PATHZ unlink drop
      err 13 = if ACCESS-DENIED then
      err 20 = if NOT-DIR then
      err 21 = if IS-DIR then
      s" error: RenameFailed" ERROR-LINE 1 EXIT-CALL
   then
   lockfd 8 FLOCK-CALL drop
   lockfd close ;

: PEND-ADD ( ptr u8 n -- )
   {: id:ptr idu:n :}
   PEND-IDS-U @ idu + PEND-IDS-RESERVE
   id 0 PEND-IDS PEND-IDS-U @ + idu BYTE-COPY
   PEND-COUNT @ 1+ 2 * PEND-RECS-RESERVE
   PEND-IDS-U @ PEND-COUNT @ 2 * PEND-RECS !
   idu PEND-COUNT @ 2 * 1+ PEND-RECS !
   idu PEND-IDS-U +! 1 PEND-COUNT +! ;

: PEND-CAPTURE ( -- )
   ACTIVE-CHAN-U @ {: chanu:n :}
   PEND-CHANS-U @ chanu + PEND-CHANS-RESERVE
   ACTIVE-CHAN-A @ 0 PEND-CHANS PEND-CHANS-U @ + chanu BYTE-COPY
   PEND-GROUP-COUNT @ 1+ 4 * PEND-GROUPS-RESERVE
   PEND-CHANS-U @ PEND-GROUP-COUNT @ 4 * PEND-GROUPS !
   chanu PEND-GROUP-COUNT @ 4 * 1+ PEND-GROUPS !
   PEND-COUNT @ PEND-GROUP-COUNT @ 4 * 2 + PEND-GROUPS !
   LIST-U @ PEND-GROUP-COUNT @ 4 * 3 + PEND-GROUPS !
   chanu PEND-CHANS-U +! 1 PEND-GROUP-COUNT +!
   0 LIST-BUF 0 LIST-RECS LIST-U @ [: PEND-ADD ;] EACH-REC ;

: PEND-COMMIT ( -- )
   PEND-GROUP-COUNT @ 0 ?do
      0 PEND-GROUPS i 4 * cells + @ {: chanoff:n :}
      0 PEND-GROUPS i 4 * 1+ cells + @ {: chanu:n :}
      0 PEND-GROUPS i 4 * 2 + cells + @ {: first:n :}
      0 PEND-GROUPS i 4 * 3 + cells + @ {: count:n :}
      0 PEND-CHANS chanoff + chanu SET-ACTIVE-CHAN
      0 PEND-IDS 0 PEND-RECS first 2 * cells + count WRITE-CURSOR
   loop ;

: UNREAD-ENTRY ( ptr u8 n -- ) {: name:ptr nameu:n :}
   name nameu CUR-MEMBER? if exit then
   name nameu READ-MESSAGE
   MSG-FROM-A @ MSG-FROM-U @ ACTIVE-WHO-A @ ACTIVE-WHO-U @ STR= if exit then
   RENDER-PLAIN ;

: COUNT-MESSAGE-ENTRY ( ptr u8 n -- )
   2drop 1 SEEN-N +! ;

: CHANNEL-SELECTED? ( ptr u8 n -- bool )
   ARG-CHAN-A @ NULL-PTR = if 2drop BB-TRUE exit then
   ARG-CHAN-A @ ARG-CHAN-U @ STR= ;

: UNREAD-CHANNEL ( ptr u8 n -- ) {: chan:ptr chanu:n :}
   chan chanu CHANNEL-SELECTED? 0= if exit then
   chan chanu MAKE-CHAN-PATH CHAN$ PATH-KIND S-IFDIR <> if exit then
   chan chanu SET-ACTIVE-CHAN
   LIST-MESSAGES
   0 SEEN-N !
   0 LIST-BUF 0 LIST-RECS LIST-U @ [: COUNT-MESSAGE-ENTRY ;] EACH-REC
   SEEN-N @ 0= if exit then
   READ-CURSOR
   0 LIST-BUF 0 LIST-RECS LIST-U @ [: UNREAD-ENTRY ;] EACH-REC
   ARG-ACK @ 0<> if PEND-CAPTURE then ;

: ACK-CHANNEL ( ptr u8 n -- ) {: chan:ptr chanu:n :}
   chan chanu CHANNEL-SELECTED? 0= if exit then
   chan chanu MAKE-CHAN-PATH CHAN$ PATH-KIND S-IFDIR <> if exit then
   chan chanu SET-ACTIVE-CHAN
   LIST-MESSAGES
   0 LIST-BUF 0 LIST-RECS LIST-U @ WRITE-CURSOR ;

: SCAN-UNREAD ( -- )
   OUT-RESET
   0 PEND-GROUP-COUNT ! 0 PEND-COUNT ! 0 PEND-IDS-U ! 0 PEND-CHANS-U !
   1 PEND-IDS-RESERVE
   IDENTITY$ ACTIVE-WHO-U ! ACTIVE-WHO-A !
   CHANNELS-LIST
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ [: UNREAD-CHANNEL ;] EACH-REC
   OUT-FLUSH
   ARG-ACK @ 0<> if PEND-COMMIT then ;

: SCAN-WATCH-UNREAD ( -- )
   OUT-RESET
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ [: UNREAD-CHANNEL ;] EACH-REC ;

: WATCH-REC@ ( n n -- ptr n )
   {: idx:n col:n :}
   0 WATCH-RECS idx 4 * col + cells + ;

: WATCH-STAT-PATH? ( ptr u8 n -- bool )
   {: path:ptr size:n :}
   size FS-PATH-CAP >= if BB-FALSE exit then
   path size FS-PATHZ WATCH-STAT stat64 0= ;

: WATCH-DEV@ ( -- n )
   WATCH-STAT FS-U16@ WATCH-STAT 2 + FS-U16@ 16 lshift or ;
: WATCH-INO@ ( -- n ) WATCH-STAT 8 + FS-U64@ ;

: WATCH-REC-NAME$ ( n -- ptr u8 n )
   {: idx:n :}
   0 WATCH-NAMES idx 0 WATCH-REC@ @ + idx 1 WATCH-REC@ @ ;

: WATCH-FILE-REC@ ( n n -- ptr n )
   {: idx:n col:n :}
   0 WATCH-FILE-RECS idx 6 * col + cells + ;

: WATCH-FILE-NAME$ ( n -- ptr u8 n )
   {: idx:n :}
   0 WATCH-FILE-NAMES idx 0 WATCH-FILE-REC@ @ +
   idx 1 WATCH-FILE-REC@ @ ;

: WATCH-SEEN? ( ptr u8 n -- bool )
   {: name:ptr size:n :}
   WATCH-DEV@ {: dev:n :} WATCH-INO@ {: ino:n :}
   WATCH-FILE-COUNT @ 0 ?do
      WATCH-PARENT-DEV @ i 2 WATCH-FILE-REC@ @ =
      WATCH-PARENT-INO @ i 3 WATCH-FILE-REC@ @ = and if
         i WATCH-FILE-NAME$ name size STR= if
            dev i 4 WATCH-FILE-REC@ @ =
            ino i 5 WATCH-FILE-REC@ @ = and {: same:bool :}
            dev i 4 WATCH-FILE-REC@ !
            ino i 5 WATCH-FILE-REC@ !
            same unloop exit
         then
      then
   loop
   WATCH-FILE-NAMES-U @ size + WATCH-FILE-NAMES-RESERVE
   name 0 WATCH-FILE-NAMES WATCH-FILE-NAMES-U @ + size BYTE-COPY
   WATCH-FILE-COUNT @ 1+ 6 * WATCH-FILE-RECS-RESERVE
   WATCH-FILE-NAMES-U @ WATCH-FILE-COUNT @ 0 WATCH-FILE-REC@ !
   size WATCH-FILE-COUNT @ 1 WATCH-FILE-REC@ !
   WATCH-PARENT-DEV @ WATCH-FILE-COUNT @ 2 WATCH-FILE-REC@ !
   WATCH-PARENT-INO @ WATCH-FILE-COUNT @ 3 WATCH-FILE-REC@ !
   dev WATCH-FILE-COUNT @ 4 WATCH-FILE-REC@ !
   ino WATCH-FILE-COUNT @ 5 WATCH-FILE-REC@ !
   size WATCH-FILE-NAMES-U +!
   1 WATCH-FILE-COUNT +!
   BB-FALSE ;

: WATCH-REMEMBER-ENTRY ( ptr u8 n -- )
   {: name:ptr size:n :}
   CHAN$ name size FILE-BUF FILE-U JOIN-INTO
   FILE$ WATCH-STAT-PATH? if name size WATCH-SEEN? drop then ;

: WATCH-REGISTER ( ptr u8 n -- )
   {: name:ptr size:n :}
   name size CHANNEL-SELECTED? 0= if exit then
   WATCH-COUNT @ 0 ?do
      i WATCH-REC-NAME$ name size STR= if unloop exit then
   loop
   name size MAKE-CHAN-PATH
   CHAN$ SYMLINK? if exit then
   CHAN$ DIR? 0= if exit then
   CHAN$ FS-PATHZ CUR-O-DIRECTORY 0 OPEN-CALL {: fd:n :}
   fd 0 < if 1 s" error: ReadFailed" FS-ERROR then
   fd close
   CHAN$ WATCH-STAT-PATH? 0= if s" error: WatchAddFailed" ERROR-LINE 1 EXIT-CALL then
   WATCH-DEV@ WATCH-PARENT-DEV !
   WATCH-INO@ WATCH-PARENT-INO !
   [: CHAN$ [: WATCH-REMEMBER-ENTRY ;] FS-LIST:EACH ;] catch
   0<> if READ-FAILED then
   CHAN$ WATCH-STAT-PATH? 0= if s" error: WatchAddFailed" ERROR-LINE 1 EXIT-CALL then
   WATCH-NAMES-U @ size + WATCH-NAMES-RESERVE
   name 0 WATCH-NAMES WATCH-NAMES-U @ + size BYTE-COPY
   WATCH-COUNT @ 1+ 4 * WATCH-RECS-RESERVE
   WATCH-NAMES-U @ WATCH-COUNT @ 0 WATCH-REC@ !
   size WATCH-COUNT @ 1 WATCH-REC@ !
   WATCH-DEV@ WATCH-COUNT @ 2 WATCH-REC@ !
   WATCH-INO@ WATCH-COUNT @ 3 WATCH-REC@ !
   size WATCH-NAMES-U +!
   1 WATCH-COUNT +! ;

: WATCH-REGISTER-CHANNELS ( -- )
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ [: WATCH-REGISTER ;] EACH-REC ;

: WATCH-IDENTITY? ( -- bool )
   WATCH-DEV@ {: dev:n :} WATCH-INO@ {: ino:n :}
   WATCH-COUNT @ 0 ?do
      dev i 2 WATCH-REC@ @ = ino i 3 WATCH-REC@ @ = and if
         BB-TRUE unloop exit
      then
   loop BB-FALSE ;

: WATCH-PARENT-U ( ptr u8 n -- n )
   {: path:ptr size:n :}
   size begin dup 0 > while
      1- dup path + c@ 47 = if exit then
   repeat ;

: WATCH-EVENT-PATH? ( ptr u8 n -- bool )
   {: path:ptr flags:n :}
   path ZLEN {: size:n :}
   path size WATCH-PARENT-U {: parentu:n :}
   path parentu WATCH-STAT-PATH? 0= if BB-FALSE exit then
   WATCH-DEV@ WATCH-CHANNELS-DEV @ =
   WATCH-INO@ WATCH-CHANNELS-INO @ = and if
      path size WATCH-STAT-PATH? exit
   then
   WATCH-IDENTITY? 0= if BB-FALSE exit then
   WATCH-DEV@ WATCH-PARENT-DEV !
   WATCH-INO@ WATCH-PARENT-INO !
   path size WATCH-STAT-PATH? 0= if BB-FALSE exit then
   path parentu 1+ + size parentu 1+ - WATCH-SEEN? {: seen:bool :}
   flags $800 and 0<> seen 0= or ;

: FS-EVENT-BODY-IMPL ( ptr u8 ptr u8 n ptr u8 ptr u8 ptr u8 -- )
   {: stream:ptr info:ptr count:n paths:ptr flags:ptr ids:ptr :}
   count 0 ?do
      flags i 4 * + FS-U16@
      flags i 4 * 2 + + FS-U16@ 16 lshift or
      dup $900 and 0<> if
         paths CELL-VIEW i cells + @ WATCH-EVENT-PTR swap WATCH-EVENT-PATH? if
            1 WATCH-WAKE ! unloop exit
         then
      else drop then
   loop ;
' FS-EVENT-BODY-IMPL FS-EVENT-BODY !


: WATCH-SETUP ( -- )
   0 WATCH-NAMES-U ! 0 WATCH-COUNT ! 0 WATCH-WAKE !
   0 WATCH-FILE-NAMES-U ! 0 WATCH-FILE-COUNT !
   5 0 ?do 0 WATCH-CONTEXT CELL-VIEW i cells + ! loop
   s" ./channels" WATCH-STAT-PATH? 0= if s" error: WatchAddFailed" ERROR-LINE 1 EXIT-CALL then
   WATCH-DEV@ WATCH-CHANNELS-DEV !
   WATCH-INO@ WATCH-CHANNELS-INO !
   NULL-PTR s" /" FS-PATHZ $08000100 CF-STRING-CALL WATCH-PATH !
   WATCH-PATH @ 0= if s" error: WatchCreateFailed" ERROR-LINE 1 EXIT-CALL then
   WATCH-PATH @ WATCH-PATH-ARRAY CELL-VIEW !
   NULL-PTR WATCH-PATH-ARRAY BYTE-VIEW 1 NULL-PTR CF-ARRAY-CALL WATCH-PATHS !
   WATCH-PATHS @ 0= if s" error: WatchCreateFailed" ERROR-LINE 1 EXIT-CALL then
   NULL-PTR s" kCFRunLoopDefaultMode" FS-PATHZ $08000100 CF-STRING-CALL WATCH-MODE !
   WATCH-MODE @ 0= if s" error: WatchCreateFailed" ERROR-LINE 1 EXIT-CALL then
   FS-EVENT TASK:SELF-CONTEXT FFI-CB:ENTRY {: callback:n :}
   NULL-PTR callback WATCH-CONTEXT BYTE-VIEW WATCH-PATHS @ -1 0.05 $14 FS-CREATE-CALL WATCH-STREAM !
   WATCH-STREAM @ 0= if s" error: WatchCreateFailed" ERROR-LINE 1 EXIT-CALL then
   WATCH-STREAM @ CF-LOOP-CALL WATCH-MODE @ FS-SCHEDULE-CALL
   WATCH-STREAM @ FS-START-CALL 0= if
      s" error: WatchStartFailed" ERROR-LINE 1 EXIT-CALL
   then ;

: WATCH-CLOSE ( -- )
   WATCH-STREAM @ FS-STOP-CALL
   WATCH-STREAM @ FS-INVALIDATE-CALL
   WATCH-STREAM @ FS-RELEASE-CALL
   WATCH-MODE @ CF-RELEASE-CALL
   WATCH-PATHS @ CF-RELEASE-CALL
   WATCH-PATH @ CF-RELEASE-CALL
   FS-EVENT FFI-CB:UNBIND ;

: WATCH-POLL-START ( -- )
   NOW-MS 2147483647 + {: limit:n :}
   ARG-T @ 0= if limit else limit WATCH-DEADLINE @ min then
   WATCH-POLL-DEADLINE ! ;

: WATCH-TIMEOUT ( -- r )
   WATCH-POLL-DEADLINE @ NOW-MS - 0 <= if
      ARG-T @ 0= if WATCH-POLL-START else 2 EXIT-CALL then
   then
   WATCH-POLL-DEADLINE @ NOW-MS - s>f 1000.0 f/ ;

: WATCH ( -- )
   IDENTITY$ ACTIVE-WHO-U ! ACTIVE-WHO-A !
   0 ARG-ACK !
   WATCH-SETUP
   ARG-T @ 0= if 0 WATCH-DEADLINE ! else NOW-MS ARG-T @ 1000 * + WATCH-DEADLINE ! then
   begin
      CHANNELS-LIST
      WATCH-REGISTER-CHANNELS
      SCAN-WATCH-UNREAD
      OUT-U @ 0 > if WATCH-CLOSE OUT-FLUSH exit then
      0 WATCH-WAKE !
      WATCH-POLL-START
      begin WATCH-WAKE @ 0= while
         WATCH-MODE @ WATCH-TIMEOUT 1 CF-RUN-CALL
         dup 3 = if
            drop ARG-T @ 0= if WATCH-POLL-START else 2 EXIT-CALL then
         else
            dup 1 = swap 2 = or if s" error: WatchStartFailed" ERROR-LINE 1 EXIT-CALL then
         then
      repeat
   again ;

: SCAN-ACK ( -- )
   IDENTITY$ ACTIVE-WHO-U ! ACTIVE-WHO-A !
   CHANNELS-LIST
   0 CHANS-BUF 0 CHANS-RECS CHANS-U @ [: ACK-CHANNEL ;] EACH-REC ;

public
: KNOWN-CMD? ( -- bool )
   CMD-A @ CMD-U @ s" init" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" post" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" log" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" unread" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" ack" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" watch" ARG= if BB-TRUE exit then
   CMD-A @ CMD-U @ s" channels" ARG= ;

: MAIN ( -- )
   PARSE-ARGS
   KNOWN-CMD? 0= if USAGE 1 EXIT-CALL then
   CMD-A @ CMD-U @ s" init" ARG= if INIT exit then
   OPEN-ROOT
   CMD-A @ CMD-U @ s" post" ARG= if POST exit then
   CMD-A @ CMD-U @ s" log" ARG= if LOG exit then
   CMD-A @ CMD-U @ s" unread" ARG= if SCAN-UNREAD exit then
   CMD-A @ CMD-U @ s" ack" ARG= if SCAN-ACK exit then
   CMD-A @ CMD-U @ s" watch" ARG= if WATCH exit then
   CMD-A @ CMD-U @ s" channels" ARG= if CHANNELS exit then
   s" unsupported command" FAIL ;
;package

: MAIN ( -- ) BB:MAIN ;
