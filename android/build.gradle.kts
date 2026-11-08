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
    // Android plugin projects can live on a different Windows drive than this app.
    // Keep their build output on the same drive so Gradle can relativize paths.
    val projectDrive = project.projectDir.toPath().root
    val rootDrive = rootProject.projectDir.toPath().root
    val newSubprojectBuildDir =
        if (projectDrive != rootDrive) {
            project.layout.projectDirectory.dir("build")
        } else {
            newBuildDir.dir(project.name)
        }
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
