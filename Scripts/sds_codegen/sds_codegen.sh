#!/bin/sh

set -e

# The root directory of the repo.
REPO_ROOT=`git rev-parse --show-toplevel`
  
# Clang can't resolve module imports if we haven't compiled those 
# module dependencies - which we haven't; we aren't actually compiling anything,
# just parsing.  
#
# Therefore, we need to replace all module imports (@import) usage with 
# normal imports (#import) for non-system frameworks.  We shouldn't need to
# do this more than once (since we'll check in the changes), but there's a 
# script to do it.
# $REPO_ROOT/Scripts/sds_codegen/sds_swap_imports.py



# When parsing Obj-c source files, we need to be able to import type 
# definitions for all types we use, otherwise clang will treat them
# as `long *`.
#
# This script enumerates all swift files in our codebase (including our Pods)
# and generates fake Obj-c headers (.h) that @interface and @protocol
# stubs for each swift class.  This is analogous to a very simplified 
# version of the "-Swift.h" files used by Swift for bridging.
$REPO_ROOT/Scripts/sds_codegen/sds_parse_swift_bridging.py --src-path  . --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes


# We parse Obj-C source files (.m only, not .mm yet) to extract simple class descriptions (class name, base class, property names and types, etc.)
$REPO_ROOT/Scripts/sds_codegen/sds_parse_objc.py --src-path SignalServiceKit/ --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes
$REPO_ROOT/Scripts/sds_codegen/sds_parse_objc.py --src-path SignalShareExtension/ --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes
$REPO_ROOT/Scripts/sds_codegen/sds_parse_objc.py --src-path SignalMessaging --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes
$REPO_ROOT/Scripts/sds_codegen/sds_parse_objc.py --src-path Signal --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes

$REPO_ROOT/Scripts/sds_codegen/sds_regenerate.sh
