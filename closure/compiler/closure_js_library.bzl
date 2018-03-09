# Copyright 2016 The Closure Rules Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Build definitions for Closure JavaScript libraries."""

load("//closure/private:defs.bzl",
     "CLOSURE_WORKER_ATTR",
     "CLOSURE_LIBRARY_BASE_ATTR",
     "CLOSURE_LIBRARY_DEPS_ATTR",
     "JS_FILE_TYPE",
     "JS_LANGUAGE_IN",
     "library_level_checks",
     "collect_js",
     "collect_runfiles",
     "convert_path_to_es6_module_name",
     "create_argfile",
     "find_js_module_roots",
     "make_jschecker_progress_message",
     "sort_roots",
     "unfurl",
     "js_checker",
)

load("//closure/compiler:closure_js_aspect.bzl",
     "closure_js_aspect")

def _closure_js_library(ctx):
  if not ctx.files.srcs and not ctx.files.externs and not ctx.attr.exports and not ctx.attr.ts_lib:
    fail("Either 'srcs', 'exports', or 'ts_lib' must be specified")
  if not ctx.files.srcs and ctx.attr.deps:
    fail("'srcs' must be set when using 'deps', otherwise consider 'exports'")
  if ctx.attr.language:
    print("The closure_js_library 'language' attribute is now removed and " +
          "is always set to " + JS_LANGUAGE_IN)

  # Create a list of the sources defined by this specific rule.
  srcs = ctx.files.srcs
  if ctx.files.externs:
    print("closure_js_library 'externs' is deprecated; just use 'srcs'")
    srcs = ctx.files.externs + srcs

  # Create a list of direct children of this rule. If any direct dependencies
  # have the exports attribute, those labels become direct dependencies here.
  deps = unfurl(ctx.attr.deps, provider="closure_js_library")

  extra_providers={}

  # The aspect converts any ts_library deps into closure_js_library's with
  # default options. Using ts_lib lets you customize those options. It's
  # like creating a closure_js_library with the same deps as the ts_library,
  # and the srcs are the tsickle outputs from the ts_library.
  if ctx.attr.ts_lib:
    lib = ctx.attr.ts_lib
    srcs = srcs + lib.typescript.es6_sources.to_list()
    deps += lib.closure_js_aspect.deps
    if hasattr(lib.typescript, 'runtime_deps'):
      deps =depset(deps, transitive=[lib.typescript.runtime_deps])
    extra_providers['typescript'] = lib.typescript

  result = js_checker(ctx,
      srcs=srcs, deps=deps,
      exports=unfurl(ctx.attr.exports),
      no_closure_library=ctx.attr.no_closure_library,
      info_file=ctx.outputs.info,stderr_file=ctx.outputs.stderr,
      ijs_file=ctx.outputs.ijs, convention=ctx.attr.convention,
      typecheck_file=ctx.outputs.typecheck, testonly=ctx.attr.testonly,
      internal_descriptors=ctx.files.internal_descriptors,
      internal_expect_failure=ctx.attr.internal_expect_failure,
      suppress=ctx.attr.suppress, worker=ctx.executable._ClosureWorker)
  
  return struct(
    files=depset(),
    closure_js_library=result.closure_js_library,
    exports=result.exports,
    # The usual suspects are exported as runfiles, in addition to raw source.
    runfiles=ctx.runfiles(
        files=srcs + ctx.files.data,
        transitive_files=(depset([] if ctx.attr.no_closure_library
                              else [ctx.file._closure_library_base,
                                    ctx.file._closure_library_deps]) |
                          collect_runfiles(deps) |
                          collect_runfiles(ctx.attr.data))),
    **extra_providers)

closure_js_library = rule(
    implementation=_closure_js_library,
    attrs={
        "convention": attr.string(default="CLOSURE"),
        "data": attr.label_list(cfg="data", allow_files=True),
        "deps": attr.label_list(
            aspects=[closure_js_aspect],
            providers=["closure_js_library"]),
        "exports": attr.label_list(
            aspects=[closure_js_aspect],
            providers=["closure_js_library"]),
        "includes": attr.string_list(),
        "no_closure_library": attr.bool(),
        "srcs": attr.label_list(allow_files=JS_FILE_TYPE),
        "ts_lib": attr.label(
            aspects = [
                closure_js_aspect,
            ],
            providers = ["typescript"],
        ),
        "suppress": attr.string_list(),

        # deprecated
        "externs": attr.label_list(allow_files=JS_FILE_TYPE),
        "language": attr.string(),

        # internal only
        "internal_descriptors": attr.label_list(allow_files=True),
        "internal_expect_failure": attr.bool(default=False),
        "_ClosureWorker": CLOSURE_WORKER_ATTR,
        "_closure_library_base": CLOSURE_LIBRARY_BASE_ATTR,
        "_closure_library_deps": CLOSURE_LIBRARY_DEPS_ATTR,
    },
    outputs={
        "info": "%{name}.pbtxt",
        "stderr": "%{name}-stderr.txt",
        "ijs": "%{name}.i.js",
        "typecheck": "%{name}_typecheck", # dummy output file
    })
