# Copyright 2018 The Closure Rules Authors. All rights reserved.
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

package(default_testonly = True)

licenses(["notice"])  # Apache 2.0

load("//closure/private:file_test.bzl", "file_test")
load("//closure:defs.bzl", "closure_js_binary")
load("//closure:defs.bzl", "closure_js_library")
load(":fake_ts_library.bzl", "fake_ts_library")

closure_js_library(
    name = "a",
    srcs = ["a.js"],
)

fake_ts_library(
    name = "b",
    srcs = ["b.js"],
    deps = [":a"],
)

closure_js_library(
    name = "c",
    srcs = ["c.js"],
    deps = [":b"],
)

file_test(
    name = "c_noWarnings",
    content = "",
    file = "c-stderr.txt",
)

fake_ts_library(
    name = "missingDep",
    srcs = ["b.js"],
    internal_expect_failure = True,
)

closure_js_library(
    name = "c_missingDep",
    srcs = ["c.js"],
    deps = [":missingDep"],
)

file_test(
    name = "c_missingDep_noWarnings",
    content = "",
    file = "c_missingDep-stderr.txt",
)

# TODO: Can't access aspect output file
# file_test(
#     name = "missingDep_causesMissingProvideError",
#     file = "missingDep-stderr.txt",
#     regexp = "CR_NOT_PROVIDED",
# )

fake_ts_library(
    name = "b_runtime_deps",
    srcs = ["b.js"],
    runtime_deps = [":a"],
)

closure_js_library(
    name = "c_runtime_deps",
    srcs = ["c.js"],
    deps = [":b_runtime_deps"],
)

file_test(
    name = "c_runtime_deps_noWarnings",
    content = "",
    file = "c_runtime_deps-stderr.txt",
)

closure_js_library(
    name = "b_wrapped",
    ts_lib = ":b",
)

closure_js_library(
    name = "c_wrapped",
    srcs = ["c.js"],
    deps = [":b_wrapped"],
)

file_test(
    name = "b_wrapped_noWarnings",
    content = "",
    file = "b_wrapped-stderr.txt",
)

file_test(
    name = "c_wrapped_noWarnings",
    content = "",
    file = "c_wrapped-stderr.txt",
)
