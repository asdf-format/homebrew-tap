class SourcextractorAsdf < Formula
  desc "SourceXtractor++ with ASDF file format support (preview)"
  homepage "https://github.com/embray/SourceXtractorPlusPlus/tree/asdf"
  url "https://github.com/embray/SourceXtractorPlusPlus/archive/fb60be0cbdbc5ae359cff81a8b17ef53d6b99769.tar.gz"
  version "1.2.0-asdf.2"
  sha256 "d8bc30c06a0947e5e70ad9a8f9e8a6e6ed8b42a860d962b25d6947c975d18c4b"
  license "LGPL-3.0-or-later"
  head "https://github.com/embray/SourceXtractorPlusPlus.git", branch: "asdf"

  bottle do
    root_url "https://github.com/asdf-format/homebrew-tap/releases/download/sourcextractor-asdf-1.2.0-asdf.2"
    rebuild 1
    sha256 arm64_tahoe:  "fc29162706a4317f7b6d9483e50096812425fee2411a3146b5616d26e8148243"
    sha256 x86_64_linux: "8bb382d6bd96d403f240545f5d46b88907138c10dc88e6d1e6d01823afe56216"
  end

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "boost"
  depends_on "boost-python3"
  depends_on "ccfits"
  depends_on "cfitsio"
  depends_on "fftw"
  depends_on "gsl"
  depends_on "libasdf"
  depends_on "libasdf-gwcs"
  depends_on "libfyaml"
  depends_on "log4cpp"
  depends_on "numpy"
  depends_on "python@3.15"
  depends_on "readline"
  depends_on "wcslib"

  uses_from_macos "ncurses"

  # Elements (the Euclid CMake framework) and Alexandria are needed to build
  # SourceXtractor++ and are linked into it at runtime, but are not formulae
  # in their own right: they are built privately into this keg's `libexec`.
  # LevMar is technically optional but we include it here too.
  resource "elements" do
    url "https://github.com/astrorama/Elements/archive/refs/tags/6.3.7.tar.gz"
    sha256 "61f973f8044730b0eba3ae560f4457da5453fddf061129c9a93a1b13ca83cc8c"

    patch do
      file "Patches/sourcextractor-asdf/elements.patch"
    end
  end

  resource "alexandria" do
    url "https://github.com/astrorama/Alexandria/archive/refs/tags/2.33.0.tar.gz"
    sha256 "96f987bf3ad9fe32e65dd8c9b4de87ccb16e11436bae45b9b3099423d1ab4b05"

    patch do
      file "Patches/sourcextractor-asdf/alexandria.patch"
    end
  end

  # Upstream (https://users.ics.forth.gr/~lourakis/levmar/) serves an
  # incomplete TLS certificate chain, so use Fedora's identical copy.
  resource "levmar" do
    url "https://src.fedoraproject.org/repo/pkgs/rpms/levmar/levmar-2.6.tgz/sha512/5b4c64b63be9b29d6ad2df435af86cd2c2e3216313378561a670ac6a392a51bbf1951e96c6b1afb77c570f23dd8e194017808e46929fec2d8d9a7fe6cf37022b/levmar-2.6.tgz"
    sha256 "3bf4ef1ea4475ded5315e8d8fc992a725f2e7940a74ca3b0f9029d9e6e94bad7"

    patch do
      file "Patches/sourcextractor-asdf/levmar.patch"
    end
  end

  # Patches for the vendored resources are in `Patches/sourcextractor-asdf`,
  # since `__END__` can only hold patches for the main source. Those below:
  # - The embedded Python config API imports astropy at load time, so every
  #   run fails without it, but it is only needed by the world coordinate
  #   helpers.
  # - ncurses' `timeout()` macro breaks newer Boost atomic headers.
  patch :DATA

  def install
    site_packages = Language::Python.site_packages(python3)
    ENV.prepend_path "CMAKE_PREFIX_PATH", libexec
    ENV["LEVMAR_ROOT_DIR"] = libexec
    # Alexandria and SourceXtractor++ use `boost::core::demangle` without
    # including it, relying on older Boost headers including it transitively.
    ENV.append "CXXFLAGS", "-include boost/core/demangle.hpp"

    # SourceXtractor++ only uses `dlevmar_dif`, which does not require LAPACK.
    resource("levmar").stage do
      system "cmake", "-S", ".", "-B", "build", "-DBUILD_DEMO=OFF", "-DHAVE_LAPACK=OFF",
                      "-DNEED_F2C=OFF", "-DLINSOLVERS_RETAIN_MEMORY=OFF",
                      "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                      "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", *std_cmake_args
      system "cmake", "--build", "build"
      (libexec/"include").install "levmar.h"
      (libexec/"lib").install "build/liblevmar.a"
    end

    # Outside `buildpath`, where SourceXtractor++ would pick them up as packages.
    vendor = buildpath.parent
    resource("elements").stage vendor/"elements"
    resource("alexandria").stage vendor/"alexandria"
    rm_r vendor/"elements/ElementsExamples"

    # Install SourceXtractor++ privately too, so that only its executable is
    # linked into `HOMEBREW_PREFIX`.
    [vendor/"elements", vendor/"alexandria", buildpath].each do |dir|
      cd dir do
        system "cmake", "-S", ".", "-B", "build",
                        "-DELEMENTS_BUILD_TESTS=OFF",
                        # Skip Elements' default compiler and linker flags, as
                        # its conda packages do. On macOS they link with
                        # `-flat_namespace`, which `brew audit` rejects.
                        "-DELEMENTS_FLAGS_SET=ON",
                        "-DUSE_SPHINX=OFF",
                        "-DPYTHON_EXPLICIT_VERSION=3",
                        "-DPYTHON_EXECUTABLE=#{python3}",
                        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                        "-DCMAKE_PREFIX_PATH=#{libexec}",
                        *std_cmake_args(install_prefix: libexec)
        system "cmake", "--build", "build"
        system "cmake", "--install", "build"
      end
    end

    (bin/"sourcextractor++").write_env_script libexec/"bin/sourcextractor++",
                                               PYTHONPATH: "#{libexec/site_packages}${PYTHONPATH:+:$PYTHONPATH}"
    # Only needed to build against Elements, and they reference Homebrew's shims.
    rm_r [libexec/"include", libexec/"lib/cmake"]
  end

  def caveats
    <<~EOS
      Python configuration files that use the world coordinate helpers (e.g.
      `get_world_parameters()`) need astropy, which is not installed by this
      formula. To install it for Homebrew's Python:
        python3.15 -m pip install --user --break-system-packages astropy
    EOS
  end

  test do
    # A 64x64 float32 image holding one Gaussian source on a noisy background.
    size = 64
    rng = Random.new(42)
    pixels = Array.new(size * size) do |idx|
      x = idx % size
      y = idx / size
      100.0 + rng.rand + (1000.0 * Math.exp(-(((x - 20)**2) + ((y - 40)**2)) / 8.0))
    end
    data = pixels.pack("e*")
    # Magic, header size, flags, compression, allocated/used/data sizes, checksum.
    # Hey, writing ASDF files is easy, even in Ruby! ;)
    block_header = [0xd3, "BLK", 48, 0, 0, *([data.bytesize] * 3)].pack("Ca3nNNQ>3x16")
    (testpath/"image.asdf").binwrite <<~YAML.b + block_header + data
      #ASDF 1.0.0
      #ASDF_STANDARD 1.6.0
      %YAML 1.1
      %TAG ! tag:stsci.edu:asdf/
      --- !core/asdf-1.1.0
      data: !core/ndarray-1.1.0 {source: 0, datatype: float32, byteorder: little, shape: [#{size}, #{size}]}
      ...
    YAML

    system bin/"sourcextractor++", "--detection-image", "image.asdf",
           "--output-catalog-filename", "catalog.txt", "--output-catalog-format", "ASCII",
           "--output-properties", "PixelCentroid"
    # One source, at the centre of the Gaussian; catalogue pixel coordinates are 1-based.
    sources = (testpath/"catalog.txt").read.lines.grep_v(/^#|^\s*$/)
    assert_equal [[21, 41]], sources.map { |line| line.split.map { |v| v.to_f.round } }
  end
end

__END__
--- a/SEMain/src/lib/ProgressNCurses.cpp
+++ b/SEMain/src/lib/ProgressNCurses.cpp
@@ -19,6 +19,7 @@
 
 #include <poll.h>
 #include <semaphore.h>
+#include <boost/thread.hpp>
 #include <ncurses.h>
 #include <fcntl.h>
 #include <readline/readline.h>
