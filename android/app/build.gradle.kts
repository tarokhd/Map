plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.irannavigator.demo"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.irannavigator.demo"
        minSdk = 24
        targetSdk = 34
        versionCode = 3
        versionName = "0.3.0-world"
    }

    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/worldAssets"))
    signingConfigs.getByName("debug").storeFile = rootProject.file(".gradle/debug.keystore")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    testImplementation("junit:junit:4.13.2")
}

val packageWorldAssets by tasks.registering(Exec::class) {
    val output = layout.buildDirectory.dir("generated/worldAssets/world")
    inputs.files(fileTree(rootProject.file("../web")) { exclude("tests/**", "README.md", "sw.js") })
    inputs.file(rootProject.file("../scripts/package_world_assets.py"))
    inputs.file(rootProject.file("../shared/runtime/native-bridge.js"))
    outputs.dir(output)
    environment("ANDROID_VENDOR_CACHE", rootProject.file(".gradle/vendor").absolutePath)
    commandLine("python3", rootProject.file("../scripts/package_world_assets.py").absolutePath, "--output", output.get().asFile.absolutePath)
}
tasks.named("preBuild").configure { dependsOn(packageWorldAssets) }

val createDebugKeystore by tasks.registering(Exec::class) {
    val key = rootProject.file(".gradle/debug.keystore")
    onlyIf { !key.exists() }
    doFirst { key.parentFile.mkdirs() }
    commandLine("${System.getProperty("java.home")}/bin/keytool", "-genkeypair", "-keystore", key.absolutePath,
        "-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android", "-keyalg", "RSA",
        "-keysize", "2048", "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US", "-noprompt")
}
tasks.matching { it.name == "validateSigningDebug" }.configureEach { dependsOn(createDebugKeystore) }
