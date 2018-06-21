workspace(name = "io_bazel_rules_closure")

load("//closure/private:java_import_external.bzl", "java_import_external")
load("//closure:repositories.bzl", "closure_repositories")

closure_repositories()

java_import_external(
    name = "com_google_guava_testlib",
    jar_sha256 = "1e7e0e728bb8d68a985115d2439ad6a36473c3e49d78a70945919731f9ac7136",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/com/google/guava/guava-testlib/24.1-jre/guava-testlib-24.1-jre.jar",
        "https://repo1.maven.org/maven2/com/google/guava/guava-testlib/24.1-jre/guava-testlib-24.1-jre.jar",
    ],
    licenses = ["notice"],  # Apache 2.0
    testonly_ = 1,
    deps = ["@com_google_guava"],
)

java_import_external(
    name = "com_google_jimfs",
    jar_sha256 = "c4828e28d7c0a930af9387510b3bada7daa5c04d7c25a75c7b8b081f1c257ddd",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/com/google/jimfs/jimfs/1.1/jimfs-1.1.jar",
        "https://repo1.maven.org/maven2/com/google/jimfs/jimfs/1.1/jimfs-1.1.jar",
        "http://maven.ibiblio.org/maven2/com/google/jimfs/jimfs/1.1/jimfs-1.1.jar",
    ],
    licenses = ["notice"],  # Apache 2.0
    testonly_ = 1,
    deps = ["@com_google_guava"],
)

java_import_external(
    name = "junit",
    jar_sha256 = "90a8e1603eeca48e7e879f3afbc9560715322985f39a274f6f6070b43f9d06fe",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/junit/junit/4.11/junit-4.11.jar",
        "https://repo1.maven.org/maven2/junit/junit/4.11/junit-4.11.jar",
        "http://maven.ibiblio.org/maven2/junit/junit/4.11/junit-4.11.jar",
    ],
    licenses = ["reciprocal"],  # Common Public License 1.0
    testonly_ = 1,
    deps = ["@org_hamcrest_core"],
)

java_import_external(
    name = "org_hamcrest_core",
    jar_sha256 = "66fdef91e9739348df7a096aa384a5685f4e875584cce89386a7a47251c4d8e9",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar",
        "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar",
        "http://maven.ibiblio.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar",
    ],
    licenses = ["notice"],  # BSD
    testonly_ = 1,
)

java_import_external(
    name = "org_mockito_all",
    jar_sha256 = "d1a7a7ef14b3db5c0fc3e0a63a81b374b510afe85add9f7984b97911f4c70605",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/org/mockito/mockito-all/1.10.19/mockito-all-1.10.19.jar",
        "https://repo1.maven.org/maven2/org/mockito/mockito-all/1.10.19/mockito-all-1.10.19.jar",
        "http://maven.ibiblio.org/maven2/org/mockito/mockito-all/1.10.19/mockito-all-1.10.19.jar",
    ],
    licenses = ["notice"],  # MIT
    testonly_ = 1,
    deps = [
        "@junit",
        "@org_hamcrest_core",
    ],
)

java_import_external(
    name = "com_google_truth",
    jar_sha256 = "25ce04464511d4a7c05e1034477900a897228cba2f86110d2ed49c956d9a82af",
    jar_urls = [
        "https://mirror.bazel.build/repo1.maven.org/maven2/com/google/truth/truth/0.39/truth-0.39.jar",
        "https://repo1.maven.org/maven2/com/google/truth/truth/0.39/truth-0.39.jar",
    ],
    licenses = ["notice"],  # Apache 2.0
    testonly_ = 1,
    deps = ["@com_google_guava"],
)
