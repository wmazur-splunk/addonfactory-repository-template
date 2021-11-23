import os
import json


class AppManifest:
    def __init__(self):
        self._manifest = None
        self._comments = []

    def read(self, content: str) -> None:
        try:
            self._manifest = json.loads(content)
        except json.JSONDecodeError:
            # Manifest file has comments.
            manifest_lines = []
            for line in content.split("\n"):
                if line.lstrip().startswith("#"):
                    self._comments.append(line)
                else:
                    manifest_lines.append(line)
            manifest = "".join(manifest_lines)
            try:
                self._manifest = json.loads(manifest)
            except json.JSONDecodeError:
                raise

    def update_addon_license(self) -> None:
        self._manifest["info"]["license"]["text"] = "LICENSES/LicenseRef-Splunk-8-2021.txt"

    def __str__(self) -> str:
        content = json.dumps(self._manifest, indent=4)
        if self._comments:
            for comment in self._comments:
                content += f"\n{comment}"
        return content


def main():
    with open(os.path.join("package", "app.manifest")) as f:
        content = f.read()
    app_manifest = AppManifest()
    app_manifest.read(content)
    app_manifest.update_addon_license()
    new_content = str(app_manifest)
    with open(os.path.join("package", "app.manifest"), "w") as f:
        f.write(new_content)


if __name__ == "__main__":
    main()
