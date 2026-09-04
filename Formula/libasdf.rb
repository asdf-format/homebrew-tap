class Libasdf < Formula
  desc "C implementation of the ASDF file format"
  homepage "https://libasdf.readthedocs.io/"
  url "https://github.com/asdf-format/libasdf/releases/download/0.1.0/libasdf-0.1.0.tar.gz"
  sha256 "efe0ad1938ee84502fea821afebe3e57e7abe9d19232c725229a93bd439cb498"
  license "BSD-3-Clause"

  bottle do
    root_url "https://github.com/asdf-format/homebrew-tap/releases/download/libasdf-0.1.0"
    sha256 cellar: :any, arm64_tahoe:  "b37c23ea90f0de23c9cee0564cbc7b9199f22a70cb060fa5afd3d4fa1add312f"
    sha256 cellar: :any, x86_64_linux: "4d12c84d09792a7efef3389f9ace20bb612c5c9a8c81b95fea6450ab167b39ff"
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

    # Upstream's AC_ARG_ENABLE([debug]) ignores $enableval, so `--disable-debug`
    # switches the debug build *on* (-g -O0 and `#define DEBUG 1`).
    # https://github.com/asdf-format/libasdf/blob/0.1.0rc2/configure.ac#L120
    # This is fixed now in main, but this workaround is needed until bumping
    # to version 0.1.0 final.
    args = std_configure_args - ["--disable-debug"]

    # Homebrew's libstatgrab bottle was built before binutils PR ld/23161 (2018)
    # demoted __bss_start/_edata/_end to PROVIDE() in the shared-object linker
    # script, so it exports them and anything linking it inherits them.
    #
    # At least, this is my guess as to why libstatgrab in particular drags in
    # these symbols
    # See https://sourceware.org/legacy-ml/binutils/2018-06/msg00020.html
    #
    # Hide just those three from the final product.  Keeping this workaround
    # here rather than upstream since AFAIK it applies very narrowly only to
    # Homebrew on Linux.
    if OS.linux?
      (buildpath/"linker-syms.map").write <<~MAP
        {
          local:
            __bss_start;
            _edata;
            _end;
        };
      MAP
      ENV.append "LDFLAGS", "-Wl,--version-script=#{buildpath}/linker-syms.map"
    end

    system "./configure", "--disable-silent-rules", "--disable-docs", *args
    system "make"

    # Upstream's tests coordinate a shared per-run temp directory that races
    # under parallel execution, so a random subset fails with `make -j`.
    # Should already be fixed on main.
    ENV.deparallelize { system "make", "check" }
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

    # Guards the version script in `install`. Fails if that workaround stops
    # applying, rather than silently going back to leaking the symbols.
    if OS.linux?
      exported = shell_output("nm -D --defined-only #{lib}/libasdf.so").lines.map { |line| line.split.last }
      assert_empty exported & ["__bss_start", "_edata", "_end"]
    end
  end
end
