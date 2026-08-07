allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    configurations.configureEach {
        // firebase_messaging already ships the Firebase Instance ID receiver.
        // ML Kit image labeling still pulls the legacy firebase-iid artifact,
        // which causes duplicate classes on Android debug/release builds.
        exclude(group = "com.google.firebase", module = "firebase-iid")
        // FlutterFire does not require the Android KTX facade at runtime here.
        // Keeping firebase-common-ktx triggers FirebaseCommonKtxRegistrar, which
        // currently crashes this app on startup on the production Android build.
        exclude(group = "com.google.firebase", module = "firebase-common-ktx")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
