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

"""Common build definitions for Closure Compiler build definitions.
"""

CSS_FILE_TYPE = FileType([".css", ".gss"])
HTML_FILE_TYPE = FileType([".html"])
JS_FILE_TYPE = FileType([".js"])
JS_LANGUAGE_DEFAULT = "ECMASCRIPT5_STRICT"
JS_TEST_FILE_TYPE = FileType(["_test.js"])
SOY_FILE_TYPE = FileType([".soy"])

JS_LANGUAGE_IN = "ECMASCRIPT_2017"
JS_LANGUAGE_OUT_DEFAULT = "ECMASCRIPT5"
JS_LANGUAGES = depset([
    "ECMASCRIPT3",
    "ECMASCRIPT5",
    "ECMASCRIPT5_STRICT",
    "ECMASCRIPT_2015",
])

CLOSURE_LIBRARY_BASE_ATTR = attr.label(
    default=Label("@com_google_javascript_closure_library//:closure/goog/base.js"),
    allow_files=True,
    single_file=True)

CLOSURE_LIBRARY_DEPS_ATTR = attr.label(
    default=Label("@com_google_javascript_closure_library//:closure/goog/deps.js"),
    allow_files=True,
    single_file=True)

CLOSURE_WORKER_ATTR = attr.label(
    default=Label("//java/io/bazel/rules/closure:ClosureWorker"),
    executable=True,
    cfg="host")

def unfurl(deps, provider=""):
  """Returns deps as well as deps exported by parent rules."""
  res = []
  for dep in deps:
    if not provider or hasattr(dep, provider):
      res.append(dep)
    if hasattr(dep, "exports"):
      for edep in dep.exports:
        if not provider or hasattr(edep, provider):
          res.append(edep)
  return res

def collect_js(ctx, deps,
               has_direct_srcs=False,
               no_closure_library=False,
               css=None):
  """Aggregates transitive JavaScript source files from unfurled deps."""
  srcs = depset()
  ijs_files = depset()
  infos = depset()
  modules = depset()
  descriptors = depset()
  stylesheets = depset()
  js_module_roots = depset()
  has_closure_library = False
  for dep in deps:
    srcs += getattr(dep.closure_js_library, "srcs", [])
    ijs_files += getattr(dep.closure_js_library, "ijs_files", [])
    infos += getattr(dep.closure_js_library, "infos", [])
    modules += getattr(dep.closure_js_library, "modules", [])
    descriptors += getattr(dep.closure_js_library, "descriptors", [])
    stylesheets += getattr(dep.closure_js_library, "stylesheets", [])
    js_module_roots += getattr(dep.closure_js_library, "js_module_roots", [])
    has_closure_library = (
        has_closure_library or
        getattr(dep.closure_js_library, "has_closure_library", False))
  if no_closure_library:
    if has_closure_library:
      fail("no_closure_library can't be used when Closure Library is " +
           "already part of the transitive closure")
  elif has_direct_srcs and not has_closure_library:
    tmp = depset([ctx.file._closure_library_base,
               ctx.file._closure_library_deps])
    tmp += srcs
    srcs = tmp
    has_closure_library = True
  if css:
    tmp = depset([ctx.file._closure_library_base,
               css.closure_css_binary.renaming_map])
    tmp += srcs
    srcs = tmp
  return struct(
      srcs=srcs,
      js_module_roots=js_module_roots,
      ijs_files=ijs_files,
      infos=infos,
      modules=modules,
      descriptors=descriptors,
      stylesheets=stylesheets,
      has_closure_library=has_closure_library)

def collect_css(deps, orientation=None):
  """Aggregates transitive CSS source files from unfurled deps."""
  srcs = depset()
  labels = depset()
  for dep in deps:
    srcs += getattr(dep.closure_css_library, "srcs", [])
    labels += getattr(dep.closure_css_library, "labels", [])
    if orientation:
      if dep.closure_css_library.orientation != orientation:
        fail("%s does not have the same orientation" % dep.label)
    orientation = dep.closure_css_library.orientation
  return struct(
      srcs=srcs,
      labels=labels,
      orientation=orientation)

def collect_runfiles(targets):
  """Aggregates data runfiles from targets."""
  data = depset()
  for target in targets:
    if hasattr(target, "closure_legacy_js_runfiles"):
      data += target.closure_legacy_js_runfiles
      continue
    if hasattr(target, "runfiles"):
      data += target.runfiles.files
      continue
    if hasattr(target, "data_runfiles"):
      data += target.data_runfiles.files
    if hasattr(target, "default_runfiles"):
      data += target.default_runfiles.files
    if hasattr(target, "closure_js_aspect") and hasattr(target, "typescript"):
      if hasattr(target.typescript, "transitive_es6_sources"):
        data += target.typescript.transitive_es6_sources
  return data

def find_js_module_roots(ctx, srcs):
  """Finds roots of JavaScript sources.

  This discovers --js_module_root paths for direct srcs that deviate from the
  working directory of ctx.action(). This is basically the cartesian product of
  generated roots, external repository roots, and includes prefixes.

  The includes attribute works the same way as it does in cc_library(). It
  contains a list of directories relative to the package. This feature is
  useful for third party libraries that weren't written with include paths
  relative to the root of a monolithic Bazel repository. Also, unlike the C++
  rules, there is no penalty for using includes in JavaScript compilation.
  """
  roots = depset([f.root.path for f in srcs if f.root.path])
  # Bazel started prefixing external repo paths with ../
  new_bazel_version = Label('@foo//bar').workspace_root.startswith('../')
  if ctx.workspace_name != "__main__":
    if new_bazel_version:
      roots += ["%s" % root for root in roots]
      roots += ["../%s" % ctx.workspace_name]
    else:
      roots += ["%s/external/%s" % (root, ctx.workspace_name) for root in roots]
      roots += ["external/%s" % ctx.workspace_name]
  if getattr(ctx.attr, "includes", []):
    for f in srcs:
      if f.owner.package != ctx.label.package:
        fail("Can't have srcs from a different package when using includes")
    magic_roots = []
    for include in ctx.attr.includes:
      if include == ".":
        prefix = ctx.label.package
      else:
        prefix = "%s/%s" % (ctx.label.package, include)
        found = False
        for f in srcs:
          if f.owner.name.startswith(include + "/"):
            found = True
            break
        if not found:
          fail("No srcs found beginning with '%s/'" % include)
      for root in roots:
        magic_roots.append("%s/%s" % (root, prefix))
    roots += magic_roots
  return roots

def sort_roots(roots):
  """Sorts roots with the most labels first."""
  return [r for _, r in sorted([(-len(r.split("/")), r) for r in roots])]

def convert_path_to_es6_module_name(path, roots):
  """Equivalent to JsCheckerHelper#convertPathToModuleName."""
  if not path.endswith(".js"):
    fail("Path didn't end with .js: %s" % path)
  module = path[:-3]
  for root in roots:
    if module.startswith(root + "/"):
      return module[len(root) + 1:]
  return module

def make_jschecker_progress_message(srcs, label):
  if srcs:
    return "Checking %d JS files in %s" % (len(srcs), label)
  else:
    return "Checking %s" % (label)

def difference(a, b):
  return [i for i in a if i not in b]

def long_path(ctx, file_):
  """Returns short_path relative to parent directory."""
  if file_.short_path.startswith("../"):
    return file_.short_path[3:]
  if file_.owner and file_.owner.workspace_root:
    return file_.owner.workspace_root + "/" + file_.short_path
  return ctx.workspace_name + "/" + file_.short_path

def create_argfile(ctx, args):
  bin_dir = ctx.configuration.bin_dir
  if hasattr(ctx, 'bin_dir'):
    bin_dir = ctx.bin_dir
  argfile = ctx.new_file(bin_dir, "%s_worker_input" % ctx.label.name)
  ctx.file_action(output=argfile, content="\n".join(args))
  return argfile

def library_level_checks(ctx, ijs_deps, srcs, executable, output, suppress = []):
  args = [
      "JsCompiler",
      "--checks_only",
      "--incremental_check_mode", "CHECK_IJS",
      "--warning_level", "VERBOSE",
      "--jscomp_off", "reportUnknownTypes",
      "--language_in", "ECMASCRIPT_2017",
      "--language_out", "ECMASCRIPT5",
      "--js_output_file", output.path,
  ]
  inputs = []
  for f in ijs_deps:
    args.append("--externs=%s" % f.path)
    inputs.append(f)
  for f in srcs:
    args.append("--js=%s" % f.path)
    inputs.append(f)
  for s in suppress:
    args.append("--suppress")
    args.append(s)
  ctx.action(
      inputs=inputs,
      outputs=[output],
      executable=executable,
      arguments=args,
      mnemonic="LibraryLevelChecks",
      progress_message="Doing library-level typechecking of " + str(ctx.label))

def js_checker(
  ctx, srcs, deps, exports, no_closure_library, info_file, stderr_file, ijs_file, typecheck_file,
  convention, testonly, worker, internal_descriptors=[], internal_expect_failure=False, suppress=[]):
  # Collect all the transitive stuff the child rules have propagated. Bazel has
  # a special nested set data structure that makes this efficient.
  js = collect_js(ctx, deps, bool(srcs), no_closure_library)

  # If closure_js_library depends on closure_css_library, that means
  # goog.getCssName() is being used in srcs to reference CSS names in the
  # dependent library. In order to guarantee renaming works, we're going to
  # pass along all those CSS library labels to closure_js_binary. Then when the
  # JS binary is compiled, we'll make sure it's linked against a CSS binary
  # which is a superset of the CSS libraries in its transitive closure.
  stylesheets = []
  for dep in deps:
    if hasattr(dep, 'closure_css_library'):
      stylesheets.append(dep.label)

  # JsChecker is a program that's run via the ClosureWorker persistent Bazel
  # worker. This program is a modded version of the Closure Compiler. It does
  # syntax checking and linting on the srcs files specified by this target, and
  # only this target. It does not output a JS file, but it does output a
  # ClosureJsLibrary protobuf info file with useful information extracted from
  # the abstract syntax tree, such as provided namespaces. This information is
  # propagated up to parent rules for strict dependency checking. It's also
  # used by the Closure Compiler when producing the final JS binary.
  args = [
      "JsChecker",
      "--label", str(ctx.label),
      "--output", info_file.path,
      "--output_errors", stderr_file.path,
      "--output_ijs_file", ijs_file.path,
      "--convention", convention,
  ]

  # Because JsChecker is an edge in the build graph, we need to declare all of
  # its input vertices.
  inputs = []

  # We want to test the failure conditions of this rule from within Bazel,
  # rather than from a meta-system like shell scripts. In order to do that, we
  # need a way to toggle the return status of the process.
  if internal_expect_failure:
    args.append("--expect_failure")

  # JsChecker wants to know if this is a testonly rule so it can throw an error
  # if goog.setTestOnly() is used.
  if testonly:
    args.append("--testonly")

  # The suppress attribute is a Closure Rules feature that makes warnings and
  # errors go away. It's a list of strings containing DiagnosticGroup (coarse
  # grained) or DiagnosticType (fine grained) codes. These apply not only to
  # JsChecker, but also propagate up to closure_js_binary.
  for s in suppress:
    args.append("--suppress")
    args.append(s)

  # Pass source file paths to JsChecker. Under normal circumstances, these
  # paths appear to be relative to the root of the repository. But they're
  # actually relative to the ctx.action working directory, which is a folder
  # full of symlinks generated by Bazel which point to the actual files. These
  # paths might contain weird bazel-out/blah/external/ prefixes. These paths
  # are by no means canonical and can change for a particular file based on
  # where the ctx.action is located.
  for f in srcs:
    args.append("--src")
    args.append(f.path)
    inputs.append(f)

  # In order for JsChecker to turn weird Bazel paths into ES6 module names, we
  # need to give it a list of path prefixes to strip. By default, the ES6
  # module name is the same as the filename relative to the root of the
  # repository, ignoring the workspace name. The exception is when the includes
  # attribute is being used, which chops the path down even further.
  js_module_roots = sort_roots(find_js_module_roots(ctx, srcs))
  for root in js_module_roots:
    args.append("--js_module_root")
    args.append(root)

  # We keep track of ES6 module names so we can guarantee that no namespace
  # collisions exist for any particular transitive closure. By making it
  # canonical, we can use it to propagate suppressions up to closure_js_binary.
  modules = [convert_path_to_es6_module_name(f.path, js_module_roots)
             for f in srcs]
  for module in modules:
    if module in js.modules:
      fail(("ES6 namespace '%s' already defined by a dependency. Check the " +
            "deps transitively. Remember that namespaces are relative to the " +
            "root of the repository unless includes=[...] is used") % module)
  if len(modules) != len(depset(modules)):
    fail("Intrarule namespace collision detected")

  # Give JsChecker the ClosureJsLibrary protobufs outputted by direct children.
  for dep in deps:
    # Polymorphic rules, e.g. closure_css_library, might not provide this.
    info = getattr(dep.closure_js_library, 'info', None)
    if info:
      args.append("--dep")
      args.append(info.path)
      inputs.append(info)

  # The list of flags could potentially be very long. So we're going to write
  # them all to a file which gets loaded automatically by our BazelWorker
  # middleware.
  argfile = create_argfile(ctx, args)
  inputs.append(argfile)

  # Add a JsChecker edge to the build graph. The command itself will only be
  # executed if something that requires its output is executed.
  ctx.action(
      inputs=inputs,
      outputs=[info_file, stderr_file, ijs_file],
      executable=worker,
      arguments=["@@" + argfile.path],
      mnemonic="Closure",
      execution_requirements={"supports-workers": "1"},
      progress_message=make_jschecker_progress_message(srcs, ctx.label))

  library_level_checks(
      ctx=ctx,
      ijs_deps=js.ijs_files,
      srcs=srcs,
      executable=worker,
      output=typecheck_file,
      suppress=suppress,
  )

  # We now export providers to any parent Target. This is considered a public
  # interface because other Skylark rules can be designed to do things with
  # this data. Other Skylark rules can even export their own provider with the
  # same name to become polymorphically compatible with this one.
  return struct(
      # Iterable<Target> of deps that should only become deps in parent rules.
      # Exports are not deps of the Target to which they belong. The exports
      # provider does not contain the exports its deps export. Targets in this
      # provider are not necessarily guaranteed to have a closure_js_library
      # provider. Rules allowing closure_js_library deps MUST also treat
      # exports of those deps as direct dependencies of the Target. If those
      # rules are library rules, then they SHOULD also provide an exports
      # attribute of their own which is propagated to parent targets via the
      # exports provider, along with any exports those exports export. The
      # exports attribute MUST NOT contain files and SHOULD NOT impose
      # restrictions on what providers a Target must have. Rules exporting this
      # provider MUST NOT allow deps to be set if srcs is empty. Aspects
      # exporting this provider MAY turn deps into exports if srcs is empty and
      # the exports attribute does not exist. The exports feature can be abused
      # by users to circumvent strict deps checking and therefore should be
      # used with caution.
      exports=exports,
      # All of the subproviders below are considered optional and MUST be
      # accessed using getattr(x, y, default). See collect_js() in defs.bzl.
      closure_js_library=struct(
          # File pointing to a ClosureJsLibrary protobuf file in pbtxt format
          # that's generated by this specific Target. It contains some metadata
          # as well as information extracted from inside the srcs files, e.g.
          # goog.provide'd namespaces. It is used for strict dependency
          # checking, a.k.a. layering checks.
          info=info_file,
          # NestedSet<File> of all info files in the transitive closure. This
          # is used by JsCompiler to apply error suppression on a file-by-file
          # basis.
          infos=js.infos + [info_file],
          ijs = ijs_file,
          ijs_files = js.ijs_files + [ijs_file],
          # NestedSet<File> of all JavaScript source File artifacts in the
          # transitive closure. These files MUST be JavaScript.
          srcs=js.srcs + srcs,
          # NestedSet<String> of all execroot path prefixes in the transitive
          # closure. For very simple projects, it will be empty. It is useful
          # for getting rid of Bazel generated directories, workspace names,
          # etc. out of module paths.  It contains the cartesian product of
          # generated roots, external repository roots, and includes
          # prefixes. This is passed to JSCompiler via the --js_module_root
          # flag. See find_js_module_roots() in defs.bzl.
          js_module_roots=js.js_module_roots + js_module_roots,
          # NestedSet<String> of all ES6 module name strings in the transitive
          # closure. These are generated from the source file path relative to
          # the longest matching root prefix. It is used to guarantee that
          # within any given transitive closure, no namespace collisions
          # exist. These MUST NOT begin with "/" or ".", or contain "..".
          modules=js.modules + modules,
          # NestedSet<File> of all protobuf definitions in the transitive
          # closure. It is used so Closure Templates can have information about
          # the structure of protobufs so they can be easily rendered in .soy
          # files with type safety. See closure_js_template_library.bzl.
          descriptors=js.descriptors + internal_descriptors,
          # NestedSet<Label> of all closure_css_library rules in the transitive
          # closure. This is used by closure_js_binary can guarantee the
          # completeness of goog.getCssName() substitutions.
          stylesheets=js.stylesheets + stylesheets,
          # Boolean indicating indicating if Closure Library's base.js is part
          # of the srcs subprovider. This field exists for optimization.
          has_closure_library=js.has_closure_library
      ),
    )
