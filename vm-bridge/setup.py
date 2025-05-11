from setuptools import setup, find_packages
import pathlib

here = pathlib.Path(__file__).parent.resolve()

with open(here / "README.md", encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="vm-bridge",
    version="1.0.0",
    description="VM Bridge - most między systemem monitorującym a maszyną wirtualną (cyfrowy bliźniak)",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Tom Sapletta",
    author_email="support@safetytwin.com",
    url="https://safetytwin.com",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "libvirt-python>=7.0.0",
        "paramiko>=2.7.2",
        "pyyaml>=5.4.1",
        "deepdiff>=5.5.0",
        "flask>=2.0.0",
        "flask-cors>=3.0.10",
        "werkzeug>=2.0.0",
        "gunicorn>=20.1.0",
        "ansible>=4.0.0"
    ],
    entry_points={
        "console_scripts": [
            "vm-bridge = main:main"
        ]
    },
    include_package_data=True,
    package_data={
        # Możesz dodać pliki konfiguracyjne, szablony itp.
    },
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: POSIX :: Linux",
        "License :: OSI Approved :: MIT License",
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: System :: Monitoring",
    ],
    test_suite="tests",
)
