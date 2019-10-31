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

"""Rule for building JavaScript binaries with Closure Compiler."""

load(
    "//closure/private:defs.bzl",
    "CLOSURE_JS_TOOLCHAIN_ATTRS",
    "JS_LANGUAGES",
    "JS_LANGUAGE_IN",
    "JS_LANGUAGE_OUT_DEFAULT",
    "collect_js",
    "collect_runfiles",
    "difference",
    "get_jsfile_path",
    "unfurl",
)
load(
    "//closure/compiler:closure_js_aspect.bzl",
    "closure_js_aspect",
)

default_ts_suppress = [
    "checkTypes",
    "strictCheckTypes",
    "reportUnknownTypes",
    "analyzerChecks",
    # "JSC_EXTRA_REQUIRE_WARNING",
    "unusedLocalVariables",
    "underscore",
]

def _impl(ctx):
    if not ctx.attr.deps:
        fail("closure_js_binary rules can not have an empty 'deps' list")
    for flag in ctx.attr.defs:
        if not flag.startswith("--") or (" " in flag and "=" not in flag):
            fail("Please use --flag=value syntax for defs")
    if ctx.attr.language not in JS_LANGUAGES.to_list():
        fail("Unknown language %s try one of these: %s" % (
            ctx.attr.language,
            ", ".join(JS_LANGUAGES.to_list()),
        ))

    deps = unfurl(ctx.attr.deps, provider = "closure_js_library")
    js = collect_js(deps, ctx.files._closure_library_base, css = ctx.attr.css)
    if not js.srcs:
        fail("There are no JS source files in the transitive closure")

    _validate_css_graph(ctx, js)

    sourcemap = None

    # This is the list of files we'll be generating.
    outputs = [ctx.outputs.bin]

    # This is the subset of that list we'll report to parent rules.
    files = [ctx.outputs.bin]

    if ctx.attr.compilation_level != 'BUNDLE':
        sourcemap = ctx.actions.declare_file(ctx.label.name+".js.map",sibling = ctx.outputs.bin)
        outputs.append(sourcemap)
        files.append(sourcemap)

    # JsCompiler is thin veneer over the Closure compiler. It's configured with a
    # superset of its flags. It introduces a private testing API, allows per-file
    # granularity of error suppression, and adds the suppression codes to printed
    # error messages.
    inputs = []
    args = [
        "--platform=native",
        "--js_output_file",
        ctx.outputs.bin.path,
        "--language_in",
        JS_LANGUAGE_IN,
        "--language_out",
        ctx.attr.language,
        "--compilation_level",
        ctx.attr.compilation_level,
        "--dependency_mode",
        ctx.attr.dependency_mode,
        "--warning_level",
        ctx.attr.warning_level,
        "--generate_exports",
        "--process_closure_primitives",
        "--define=goog.json.USE_NATIVE_JSON",
        "--hide_warnings_for=closure/goog/base.js",
    ]

    if sourcemap:
        args.append("--create_source_map")
        args.append(sourcemap.path)

    if not ctx.attr.debug:
        args.append("--define=goog.DEBUG=false")

    # For the sake of simplicity we're going to assume that the sourcemap file is
    # stored within the same directory as the compiled JS binary; therefore, the
    # JSON sourcemap file should cite that file as relative to itself.
    args.append("--source_map_location_mapping")
    args.append("%s|%s" % (ctx.outputs.bin.path, ctx.outputs.bin.basename))

    # By default we're going to include the raw sources in the .js.map file. This
    # can be disabled with the nodefs attribute.
    args.append("--source_map_include_content")

    # Some flags we're merely pass along as-is from our attributes.
    if ctx.attr.formatting:
        args.append("--formatting")
        args.append(ctx.attr.formatting)
    if ctx.attr.debug:
        args.append("--debug")
    for entry_point in ctx.attr.entry_points:
        args.append("--entry_point")
        args.append(entry_point)

    # It would be quite onerous to put an /** @export */ and entry_point on every
    # single testFoo, setUp, and tearDown function. This undocumented flag is a
    # godsend for testing in ADVANCED mode that releases us from this toil.
    if ctx.attr.testonly:
        args.append("--export_test_functions")

    # Those who write JavaScript on the hardest difficulty setting shall be
    # rewarded accordingly.
    if ctx.attr.compilation_level == "ADVANCED":
        args.append("--use_types_for_optimization")

    if ctx.attr.output_wrapper:
        args.append("--output_wrapper=" + ctx.attr.output_wrapper)
        if ctx.attr.output_wrapper == "(function(){%output%}).call(this);":
            args.append("--assume_function_wrapper")
    if ctx.outputs.property_renaming_report:
        report = ctx.outputs.property_renaming_report
        files.append(report)
        outputs.append(report)
        args.append("--property_renaming_report")
        args.append(report.path)

    # All sources must conform to these protos.
    for config in ctx.files.conformance:
        args.append("--conformance_configs")
        args.append(config.path)
        inputs.append(config)

    # It is better to put a suppress code on the closure_js_library rule that
    # defined the source responsible for an error. We provide an escape hatch for
    # situations in which that would be unfeasible or burdensome.
    for code in ctx.attr.suppress_on_all_sources_in_transitive_closure+default_ts_suppress:
        args.append("--jscomp_off")
        args.append(code)

    # In order for us to feel comfortable creating an optimal experience for 99%
    # of users, we need to provide an escape hatch for the 1%. For example, a
    # user wishing to support IE6 might want to pass the attribute `nodefs =
    # ["--define=goog.json.USE_NATIVE_JSON"]`. Cf. nocopts in cc_library().
    if ctx.attr.nodefs:
        args = [arg for arg in args if arg not in ctx.attr.nodefs]

    all_args = ctx.actions.args()
    all_args.add_all(args)

    # We shall now pass all transitive sources, including externs files.
    for src in js.srcs.to_list():
        inputs.append(src)
        if src.path.endswith(".zip"):
            all_args.add("--jszip")
        all_args.add_all(
            [src],
            map_each = get_jsfile_path,
            expand_directories = True,
        )

    # As a matter of policy, we don't add attributes to this rule just because we
    # can. We only add attributes when the Skylark code adds value beyond merely
    # passing those flags along to the Closure Compiler. So users wishing to use
    # the more niche features of the Closure Compiler can do things like pass
    # `defs = ["--polymer_pass"]` to add type safety to Polymer, or the user
    # could pass `defs = ["--env=CUSTOM"]` to get rid of browser externs and
    # slightly speed up compilation.
    all_args.add_all(ctx.attr.defs)

    # Insert an edge into the build graph that produces the minified version of
    # all JavaScript sources in the transitive closure, sans dead code.

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable._google_closure_compiler,
        arguments = [all_args],
        mnemonic = "Closure",
        progress_message = "Compiling %d JavaScript files to %s" % (
            len(js.srcs.to_list()),
            ctx.outputs.bin.short_path,
        ),
    )

    # This data structure is not information about the compilation but rather a
    # promise to compile. Its fulfillment is the prerogative of ancestors which
    # are free to ignore the binary in favor of the raw sauces propagated by the
    # closure_js_library provider, in which case, no compilation is performed.
    return struct(
        files = depset(files),
        closure_js_library = js,
        closure_js_binary = struct(
            bin = ctx.outputs.bin,
            map = sourcemap,
            language = ctx.attr.language,
        ),
        runfiles = ctx.runfiles(
            files = files + ctx.files.data,
            transitive_files = depset(transitive = [
                collect_runfiles(deps),
                collect_runfiles([ctx.attr.css]),
                collect_runfiles(ctx.attr.data),
            ]),
        ),
    )

def _validate_css_graph(ctx, js):
    if ctx.attr.css:
        missing = difference(js.stylesheets, ctx.attr.css.closure_css_binary.labels)
        if missing:
            fail("Dependent JS libraries depend on CSS libraries that weren't " +
                 "compiled into the referenced CSS binary: " +
                 ", ".join(missing))
    elif js.stylesheets:
        fail("Dependent JS libraries depend on CSS libraries, but the 'css' " +
             "attribute is not set to a closure_css_binary that provides the " +
             "rename mapping for those CSS libraries")

closure_js_binary = rule(
    implementation = _impl,
    attrs = dict({
        "compilation_level": attr.string(default = "ADVANCED"),
        "css": attr.label(providers = ["closure_css_binary"]),
        "debug": attr.bool(default = False),
        "defs": attr.string_list(),
        "dependency_mode": attr.string(default = "LOOSE"),
        "deps": attr.label_list(
            providers = ["closure_js_library"],
        ),
        "entry_points": attr.string_list(),
        "formatting": attr.string(),
        "language": attr.string(default = JS_LANGUAGE_OUT_DEFAULT),
        "nodefs": attr.string_list(),
        "output_wrapper": attr.string(),
        "property_renaming_report": attr.output(),
        "warning_level": attr.string(default = "VERBOSE"),
        "data": attr.label_list(allow_files = True),
        "conformance": attr.label_list(allow_files = True),
        "suppress_on_all_sources_in_transitive_closure": attr.string_list(),

        # internal only
        "internal_expect_failure": attr.bool(default = False),
        "internal_expect_warnings": attr.bool(default = False),
        "_google_closure_compiler": attr.label(
            default = Label(
                "@npm//google-closure-compiler/bin:google-closure-compiler",
            ),
            executable = True,
            cfg = "host",
        ),
    }, **CLOSURE_JS_TOOLCHAIN_ATTRS),
    outputs = {
        "bin": "%{name}.js",
    },
)
