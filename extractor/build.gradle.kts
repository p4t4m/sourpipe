// Compiles the pinned NewPipeExtractor (vendor/NewPipeExtractor, see upstream.lock and patches/)
// plus the SourPipe bridge into one JavaScript bundle for JavaScriptCore.
plugins {
    java
    id("org.teavm") version "0.16.0"
}

repositories {
    mavenCentral()
    maven("https://jitpack.io")
}

val upstream = rootProject.file("../vendor/NewPipeExtractor")

java {
    toolchain.languageVersion = JavaLanguageVersion.of(21)
}

sourceSets {
    main {
        java {
            srcDir("src/bridge/java")
            srcDir("src/overlay/java")
            srcDir("src/shim/java")
            srcDir(upstream.resolve("extractor/src/main/java"))
            srcDir(upstream.resolve("timeago-parser/src/main/java"))
        }
        resources.srcDir("src/shim/resources")
    }
}

dependencies {
    implementation("com.github.TeamNewPipe:nanojson:e9d656ddb49a412a5a0a5d5ef20ca7ef09549996")
    implementation("org.jsoup:jsoup:1.23.2")
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    compileOnly(teavm.libs.jsoApis)
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-Xlint:none")
    options.isWarnings = false
    options.release = 17
}

teavm {
    js {
        mainClass = "sourpipe.bridge.Main"
        moduleType = org.teavm.gradle.api.JSModuleType.NONE
        targetFileName = "extractor.js"
        obfuscated = true
        optimization = org.teavm.gradle.api.OptimizationLevel.BALANCED
        sourceMap = false
    }
}

tasks.register<Copy>("bundle") {
    description = "Builds the JavaScript and copies it into the iOS app's resources."
    dependsOn("generateJavaScript")
    from(layout.buildDirectory.dir("generated/teavm/js")) {
        include("extractor.js")
        // Xcode can treat .js as a source file; .jsbundle is always a plain resource.
        rename { "extractor.jsbundle" }
    }
    into(rootProject.file("../ios/SourPipe/Resources"))
}
