# DO NOT EDIT -- bazel run //closure/library:regenerate -- "$PWD"

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

load("//closure:defs.bzl", "closure_js_library")

closure_js_library(
    name = "all_js",
    exports = [":lite"],
)

closure_js_library(
    name = "lite",
    srcs = ["@com_google_javascript_closure_library//:closure/goog/streams/lite.js"],
    lenient = True,
)
