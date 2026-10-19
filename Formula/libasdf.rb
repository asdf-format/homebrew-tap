class Libasdf < Formula
  desc "C implementation of the ASDF file format"
  homepage "https://libasdf.readthedocs.io/"
  url "https://github.com/asdf-format/libasdf/releases/download/0.2.2/libasdf-0.2.2.tar.gz"
  sha256 "cbccf73c2dbd2093dfe8b68f2e366ff7a4b87754f30b4b2d60eb51b3b1a02808"
  license "BSD-3-Clause"

  bottle do
    root_url "https://github.com/asdf-format/homebrew-tap/releases/download/libasdf-0.2.2"
    sha256 cellar: :any, arm64_tahoe:  "7d74268c83d69bccc8dbc38bac69c738f01b82f1d4b287b098e10e1a8da27415"
    sha256 cellar: :any, x86_64_linux: "3f8704b495cdfeaa8a8e0d8c3351a5312026287a5af89500da1f24c477fa9f46"
  end

  head do
    url "https://github.com/asdf-format/libasdf.git", branch: "main"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "libtool" => :build
  end

  depends_on "pkgconf" => :build
  depends_on "libfyaml"
  depends_on "libmd"
  depends_on "libstatgrab"
  depends_on "lz4"

  uses_from_macos "bzip2"
  uses_from_macos "zlib"

  on_macos do
    depends_on "argp-standalone"
  end

  # libasdf installs an `asdf` command-line tool, as does the asdf-vm version manager.
  conflicts_with "asdf", because: "both install an `asdf` binary"

  def install
    system "./autogen.sh" if build.head?
    system "./configure", "--disable-silent-rules", "--disable-docs", *std_configure_args
    system "make"
    system "make", "check"
    system "make", "install"
  end

  test do
    (testpath/"test.c").write <<~C
      #include <asdf.h>

      int main(void) {
          asdf_file_t *file = asdf_open(NULL);
          if (file == NULL)
              return 1;
          asdf_set_string0(file, "name", "homebrew");
          asdf_set_int64(file, "answer", 42);
          if (asdf_write_to(file, "out.asdf") != 0)
              return 1;
          asdf_close(file);
          return 0;
      }
    C

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-lasdf", "-o", "test"
    system "./test"
    assert_path_exists testpath/"out.asdf"
    assert_match "homebrew", shell_output("#{bin}/asdf info out.asdf")
  end
end
