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

def _closure_js_library_impl(ctx):
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
    extra_providers['typescript'] = _process_typescript(ctx, lib)

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
    clutz_dts=ctx.attr.internal_dts.clutz_dts,
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

def _process_typescript(ctx, ts_lib):
  """Updates the typescript provider to include exports."""
  if not(ctx.attr.exports):
    return ts_lib.typescript
  ts_dict={}
  for a in dir(ts_lib.typescript):
    v = getattr(ts_lib.typescript, a, None)
    if v != None:
      ts_dict[a] = v
  decls=[ts_lib.typescript.declarations]
  for dep in unfurl(ctx.attr.exports, "typescript"):
    decls.append(dep.typescript.declarations)
  ts_dict['declarations']=depset(transitive=decls)
  return struct(**ts_dict)

_closure_js_library = rule(
    implementation=_closure_js_library_impl,
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
        "internal_dts": attr.label(providers=["clutz_dts"]),
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

# Rule for generating .d.ts files. This is a separate rule from 
# closure_js_library so that users don't have to build clutz if they
# never need to generate .d.ts files. Also it also the .d.ts files to have
# a label so users (or ides) can request they be built from a command line.
# This would not be true if they're generated by non-default outputs or by
# an aspect.
def _gen_dts_impl(ctx):
  if ctx.attr.ts_lib:
    return struct(clutz_dts=ctx.attr.ts_lib.typescript.declarations)
  srcs = ctx.files.srcs
  output = ctx.outputs.output
  args = ctx.actions.args()
  args.add("--partialInput")
  args.add("-o")
  args.add(output.path)
  args.add(srcs)
  ctx.action(
      inputs=srcs,
      outputs=[output],
      executable=ctx.executable._clutz,
      arguments=[args],
      mnemonic="Clutz",
      progress_message="Running Clutz on %d JS files %s" % (len(srcs), ctx.label,))
  dts_files = [output]
  if ctx.file.internal_base:
    dts_files.append(ctx.file.internal_base)
  return struct(clutz_dts=dts_files)

_gen_dts = rule(
    implementation=_gen_dts_impl,
    attrs={
        "srcs": attr.label_list(allow_files=JS_FILE_TYPE),
        "output": attr.output(),
        "ts_lib": attr.label(
            providers = ["typescript"],
        ),
        # internal only
        "_clutz": attr.label(
            default = Label("@io_angular_clutz//:clutz"),
            executable = True,
            cfg = "host",
        ),
        "internal_base":attr.label(
            allow_single_file=True,
            ),
    },
)

def closure_js_library(**kwargs):
  name = kwargs["name"]
  _closure_js_library(internal_dts=name+"-gen_dts", **kwargs)
  dts_srcs = kwargs.get("srcs", [])+kwargs.get("externs",[])
  base=Label("@io_bazel_rules_closure//closure/library:base.d.ts")
  if kwargs.get('no_closure_library'):
    base=None
  # Use tags=["manual"] so that bazel test foo:all doesn't build the .d.ts files.
  output = name+".d.ts"
  ts_lib = kwargs.get("ts_lib", None)
  if ts_lib:
    output = None

  _gen_dts(
      name=name+"-gen_dts",
      srcs=dts_srcs,
      output=output,
      ts_lib=ts_lib,
      tags=["manual"],
      internal_base=base)