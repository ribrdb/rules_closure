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

load("//closure/private:defs.bzl",
   "CLOSURE_WORKER_ATTR",
   "JS_FILE_TYPE",
   "collect_js",
   "collect_runfiles",
   "convert_path_to_es6_module_name",
   "create_argfile",
   "find_js_module_roots",
   "make_jschecker_progress_message",
   "unfurl",
   "js_checker",
)

def _closure_js_aspect_impl(target, ctx):
  if hasattr(target, "closure_js_library"):
    return struct()
  if not(hasattr(target, "typescript")):
    return []
  internal_expect_failure = getattr(target, "internal_expect_failure", False)
  srcs = target.typescript.es6_sources.to_list()
  deps = unfurl(ctx.rule.attr.deps, provider="closure_js_library")
  if hasattr(ctx.rule.attr, 'runtime_deps') and ctx.rule.attr.runtime_deps:
    deps += unfurl(ctx.rule.attr.runtime_deps, provider="closure_js_library")
  no_closure_library = True
  for dep in deps:
    if dep.closure_js_library.has_closure_library:
      no_closure_library = False
      break
  testonly = getattr(ctx.rule.attr, 'testonly', False)
  
  result = js_checker(ctx,
    srcs=srcs, deps=deps,
    exports=getattr(ctx.rule.attr, 'exports',[]),
    no_closure_library=no_closure_library,
    info_file=ctx.new_file(ctx.genfiles_dir, '%s.pbtxt'%ctx.label.name),
    stderr_file=ctx.new_file(ctx.genfiles_dir, '%s-stderr.txt'%ctx.label.name),
    ijs_file=ctx.new_file(ctx.genfiles_dir, '%s.i.js'%ctx.label.name),
    typecheck_file=ctx.new_file(ctx.genfiles_dir, '%s_typecheck'%ctx.label.name),
    convention='NONE', worker=ctx.executable._ClosureWorkerAspect, testonly=testonly,
    internal_expect_failure=internal_expect_failure,
    suppress=["checkTypes","reportUnknownTypes"])
  return struct(
    closure_js_aspect=struct(deps=deps),
    closure_js_library=result.closure_js_library,
    exports=result.exports,
  )

closure_js_aspect = aspect(
  implementation=_closure_js_aspect_impl,
  attr_aspects=["deps", "sticky_deps", "exports", "runtime_deps"],
  attrs={"_ClosureWorkerAspect": CLOSURE_WORKER_ATTR})
