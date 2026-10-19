class LibasdfGwcs < Formula
  desc "GWCS plugin for libasdf"
  homepage "https://libasdf-gwcs.readthedocs.io/"
  url "https://github.com/asdf-format/libasdf-gwcs/releases/download/0.2.1/libasdf-gwcs-0.2.1.tar.gz"
  sha256 "04e462c781ea392137e3faf9c8e20d5ac69b4ab6d6dcdec82a0d33467d4046da"
  license "BSD-3-Clause"

  bottle do
    root_url "https://github.com/asdf-format/homebrew-tap/releases/download/libasdf-gwcs-0.2.1"
    sha256 cellar: :any, arm64_tahoe:  "a3399801c043889bd01e45e687718864b6d7ac0edaf1648f10b39ca2c8bb88af"
    sha256 cellar: :any, x86_64_linux: "561160de34a9b757ebc3673b243a4dc14f16110e064506ad902f1ca152e05b79"
  end

  head do
    url "https://github.com/asdf-format/libasdf-gwcs.git", branch: "main"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "libtool" => :build
  end

  depends_on "pkgconf" => [:build, :test]
  depends_on "libasdf"
  depends_on "libfyaml"

  def install
    system "./autogen.sh" if build.head?
    system "./configure", "--disable-silent-rules", "--disable-docs", *std_configure_args
    system "make"
    system "make", "check"
    system "make", "install"
  end

  test do
    (testpath/"test.asdf").write <<~YAML
      #ASDF 1.0.0
      #ASDF_STANDARD 1.6.0
      %YAML 1.1
      %TAG ! tag:stsci.edu:
      --- !asdf/core/asdf-1.1.0
      wcs: !gwcs/wcs-1.4.0
        name: test
        steps:
        - !gwcs/step-1.3.0
          frame: !gwcs/frame2d-1.2.0 {name: detector}
          transform: !asdf/transform/concatenate-1.2.0
            forward:
            - !asdf/transform/scale-1.2.0 {factor: 2.0}
            - !asdf/transform/scale-1.2.0 {factor: 3.0}
        - !gwcs/step-1.3.0
          frame: !gwcs/frame2d-1.2.0 {name: world}
          transform: null
      ...
    YAML

    (testpath/"test.c").write <<~C
      #include <stdio.h>
      #include <asdf.h>
      #include <asdf/gwcs/gwcs.h>

      int main(void) {
          asdf_file_t *file = asdf_open("test.asdf", "r");
          asdf_gwcs_t *wcs = NULL;
          if (!file || asdf_get_gwcs(file, "wcs", &wcs) != ASDF_VALUE_OK)
              return 1;
          asdf_gwcs_eval_t *eval = asdf_gwcs_eval_create(file, wcs, NULL, NULL);
          double x = 1.5, y = 2.5;
          if (!eval || asdf_gwcs_eval_2d(eval, &x, &y, &x, &y, 1) != ASDF_GWCS_OK)
              return 1;
          printf("%g %g\\n", x, y);
          return 0;
      }
    C

    flags = shell_output("pkgconf --cflags --libs libasdf-gwcs").chomp.split
    system ENV.cc, "test.c", *flags, "-o", "test"
    assert_equal "3 7.5\n", shell_output("./test")
  end
end
