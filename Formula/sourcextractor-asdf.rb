class SourcextractorAsdf < Formula
  desc "SourceXtractor++ with ASDF file format support (preview)"
  homepage "https://github.com/embray/SourceXtractorPlusPlus/tree/asdf"
  url "https://github.com/embray/SourceXtractorPlusPlus/archive/7ac989b47a5ebb1ad0ffbe3e31a614a3408188a9.tar.gz"
  version "1.2.0-asdf.1"
  sha256 "6a6d5371d5965d1fc7f6e1528b20540a305c4f9f95ed40ad34c994f7fd1b292c"
  license "LGPL-3.0-or-later"
  head "https://github.com/embray/SourceXtractorPlusPlus.git", branch: "asdf"

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
  depends_on "log4cpp"
  depends_on "numpy"
  depends_on "python@3.14"
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
  end

  resource "alexandria" do
    url "https://github.com/astrorama/Alexandria/archive/refs/tags/2.33.0.tar.gz"
    sha256 "96f987bf3ad9fe32e65dd8c9b4de87ccb16e11436bae45b9b3099423d1ab4b05"
  end

  # Upstream (https://users.ics.forth.gr/~lourakis/levmar/) serves an
  # incomplete TLS certificate chain, so use Fedora's identical copy.
  resource "levmar" do
    url "https://src.fedoraproject.org/repo/pkgs/rpms/levmar/levmar-2.6.tgz/sha512/5b4c64b63be9b29d6ad2df435af86cd2c2e3216313378561a670ac6a392a51bbf1951e96c6b1afb77c570f23dd8e194017808e46929fec2d8d9a7fe6cf37022b/levmar-2.6.tgz"
    sha256 "3bf4ef1ea4475ded5315e8d8fc992a725f2e7940a74ca3b0f9029d9e6e94bad7"
  end

  # The embedded Python config API imports astropy at load time, so every run
  # fails without it, but it is only needed by the world coordinate helpers.
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
      # The obsolete BSD `finite()` is no longer declared by the macOS SDK.
      # Just use C99 standard isfinite()
      inreplace "compiler.h", "#define LM_FINITE finite ", "#define LM_FINITE isfinite "
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

    # `distutils` was removed in Python 3.12.
    inreplace vendor/"elements/cmake/ElementsLocations.cmake",
              /"from distutils\.sysconfig import .*"$/,
              "\"print('#{site_packages}')\""
    # CMake 4 removed the OLD behaviour of this (macOS-only) policy.
    inreplace vendor/"elements/cmake/ElementsProjectConfig.cmake",
              "cmake_policy(SET CMP0042 OLD)", "cmake_policy(SET CMP0042 NEW)"
    # The macOS branch uses an undeclared `path` type and does not compile.
    # Questionable whether it ever did. Will have to see what their conda
    # package does...  Weird!
    inreplace vendor/"elements/ElementsKernel/src/Lib/ModuleInfo.cpp" do |s|
      s.gsub! "  path         self_proc{};\n", ""
      s.gsub! "path self_exe = path(string(pathbuf));", "Path::Item self_exe{string(pathbuf)};"
    end
    # ncurses' `timeout()` macro breaks newer Boost atomic headers.
    inreplace "SEMain/src/lib/ProgressNCurses.cpp", "#include <ncurses.h>\n",
                                                    "#include <boost/thread.hpp>\n#include <ncurses.h>\n"

    # Install SourceXtractor++ privately too, so that only its executable is
    # linked into `HOMEBREW_PREFIX`.
    [vendor/"elements", vendor/"alexandria", buildpath].each do |dir|
      cd dir do
        # Boost >= 1.89 no longer ships the `boost_system` stub library.
        inreplace Dir["*/CMakeLists.txt"], /(find_package\(Boost[^)]*) system\b/, "\\1", audit_result: false
        system "cmake", "-S", ".", "-B", "build",
                        "-DELEMENTS_BUILD_TESTS=OFF",
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
        python3.14 -m pip install --user --break-system-packages astropy
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
--- a/SEImplementation/python/sourcextractor/config/model_fitting.py
+++ b/SEImplementation/python/sourcextractor/config/model_fitting.py
@@ -28,8 +28,6 @@
     import pyston
 except ImportError:
     warnings.warn('Could not import pyston: running outside sourcextractor?', ImportWarning)
-from astropy import units as u
-from astropy.coordinates import SkyCoord

 from .measurement_images import MeasurementGroup

@@ -854,6 +852,16 @@
     -------
     SkyCoord
     """
+    # astropy is only needed here, so don't make it a hard dependency of the whole config API
+    try:
+        from astropy import units as u
+        from astropy.coordinates import SkyCoord
+    except ImportError as exc:
+        raise ImportError(
+            'astropy is required for computing world coordinate angles and separations '
+            '(e.g. get_world_parameters()); install it with: pip install astropy'
+        ) from exc
+
     coord = pixel_to_world_coordinate(x, y)
     sky_coord = SkyCoord(ra=coord.ra * u.degree, dec=coord.dec * u.degree)
     return sky_coord
