// Hands instagram.com pages to the app this extension ships in.
// Shipped inside Sparkle as a Safari web extension.

(function () {
    "use strict";

    if (window.top !== window.self) return;

    // Safari is only sure to follow a custom URL scheme while the page has
    // user activation. Outside it Safari accepts the occasional attempt and
    // answers repeated ones with an "address is invalid" alert, so a page is
    // offered to the app exactly once:
    //   1. on load, which Safari usually accepts for a fresh page
    //   2. failing that (the setting was off at load), on the first real tap
    //   3. a banner covers the loads Safari ignores
    //
    // The page URL travels whole inside a scheme only this install registers,
    // and the app routes it as a universal link. Another Instagram copy on the
    // device never sees it, and every link type Instagram understands works.

    // The build rewrites this line when the app is given a custom bundle ID.
    var APP_SCHEME = "sparkle-ig";

    var DISMISS_KEY = "__spkOpenInAppDismissed";
    var ICON = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAABY2lDQ1BrQ0dDb2xvclNwYWNlRGlzcGxheVAzAAAokX2QsUvDUBDGv1aloHUQHRwcMolDlJIKuji0FURxCFXB6pS+pqmQxkeSIgU3/4GC/4EKzm4Whzo6OAiik+jm5KTgouV5L4mkInqP435877vjOCA5bnBu9wOoO75bXMorm6UtJfWMBL0gDObxnK6vSv6uP+P9PvTeTstZv///jcGK6TGqn5QZxl0fSKjE+p7PJe8Tj7m0FHFLshXyieRyyOeBZ71YIL4mVljNqBC/EKvlHt3q4brdYNEOcvu06WysyTmUE1jEDjxw2DDQhAId2T/8s4G/gF1yN+FSn4UafOrJkSInmMTLcMAwA5VYQ4ZSk3eO7ncX3U+NtYMnYKEjhLiItZUOcDZHJ2vH2tQ8MDIEXLW54RqB1EeZrFaB11NguASM3lDPtlfNauH26Tww8CjE2ySQOgS6LSE+joToHlPzA3DpfAEDp2ITpJYOWwAAAARjSUNQDA0AAW4D4+8AAAA4ZVhJZk1NACoAAAAIAAGHaQAEAAAAAQAAABoAAAAAAAKgAgAEAAAAAQAAAGCgAwAEAAAAAQAAAGAAAAAAivt9dAAAAZ1pVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDYuMC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6ZXhpZj0iaHR0cDovL25zLmFkb2JlLmNvbS9leGlmLzEuMC8iPgogICAgICAgICA8ZXhpZjpQaXhlbFhEaW1lbnNpb24+NTEyPC9leGlmOlBpeGVsWERpbWVuc2lvbj4KICAgICAgICAgPGV4aWY6UGl4ZWxZRGltZW5zaW9uPjUxMjwvZXhpZjpQaXhlbFlEaW1lbnNpb24+CiAgICAgIDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgq4L0hXAAA9BElEQVR4Aa2dCbCtVXXn13fGe88d3nQZ3gMeU4AnvIcoiCKDgEgGEUMZzaB00sZKV1d3JSZdnTJd6W6rrIrp6nRsO+lOYlIdE+OQGAFxCmJAUMABlNkHMskD3gPeeOd7pq//v7X2Pufcy8UYO/vdffa09t5r/9faaw/fd84r7F/YlbfeWnv0nks3zs3bTLlgW/od22h9myl61mpUbWujabtqhe0s+nZcYTY+VjGrVM0aStQUL1Ka0JRPWKiskso8TVl2KitKedIKsydP/a72vWFa/VuZy82WVe9Z5T1obXvAerZXDS5axfZbv3vExvv7rdrYb1d+9VBx2WVdtfIv5pzv/5/W9vxhOX7/bju7s2KvX2nb+b227eh2bFunbRvKrjULsVvRQPF9eZVbT3llv7SKEKgIKeEsX1qNuFAgD4wr4q6mfNJ1xQf5KitSPWioXzidaDxOiARCMIUkmPPJhZ4S6uAqKq9JwvVqXb5mtWrF2zekVBU/FVuu1orZeq3yXK1e2S2yb1vD7rTj7f7i/cWiN/JjfvzYArjhV8pdC/P2zsVFu3ppUaAvW7G0ZNZeEcAdwC7Ff98HWZSALXBd5QgBteeAVqVugAXwVeUBSlXgZmEgmABe7SEEDZQyzSKnRQAMgjoOuhLUITeXCU6vC+TQ4vmkvYhHOChL+aRdwJp2taJqjVrdWvUxa401rKz3yvHxxu56s/65yph9vPjr4n5v9p/5kfv/kat97OfLV64s2G/Pz9k1y/M2LlNj0nwrBW4ArlAAO5CyAQBfoOkIBDDJA2yAdy0mBPwAsJbiIZDIq4pLfAgKAQXI1GcAEUIrIJXheR4fAu7gq5Ayjyv0hGTFbIoS4pEdxcpP6agfZeTVJJTx2phtbE1bfay2NNEav97qlf9efLq4l7o/qoOfH8nddG05seeAvW9uzt47f8QmZwV8XxoO8G5M0XaBl7UdsIi7tgt0jXEAuIOrvABZZYrXHfjIQ0gOuA9UbYhDF5ALKcVFExoOSACIgALArPEeJmgBDRfgxwzJ4EZJBj6VQQvThP6ZQiVyP7l+o1KzLa1N1mqNz4+NjX3YNjY+WHysWEjVfmiQ2/6hRH/5lnKHzM1fLMzahQcOm3W7Ws0S8KWAkBRcO2EM4N1uu+ZHvms+wtCAqloUKA8hAJ7A1mxoVMjDHAF+0GJm8syAnvZJu6ARsMoZQKwBCDj0OAQTJsgpXPjDIVKHdSG7YSyB7AUBPlHKS/oj7kKJOFqVhUHfY1ocjpk8yhqtxh3VVus9xWeau6n/w9xo3+vSfeSnyzcszdnfHDlkx88uio1+d6j1gKwW0FYacjuPZiIQvDKHQukJeHkA9MGE1lc8r+fAYn5YGzLw2f5nYTHgnOczTGaAMNaIbPMRQtJi5wvO8HyGgDxB2rODNsr5zOkEMlkDx3gRRYwBWmavj0eNMd6awk1jm2xqcuqZ2ljjXcXnNt02qL5OJDhbp4CsP7u8vFIL7KcOHbZNi8s9AS/fZy83lDwNhAASOBl85bvGihbzAvi+61F+kUCvS+sRgM8KaNCoAcik0XoNkDz53FcWAum8DgBmBph8ekcrcZEfcU+naBaUE/nHy4FPPo5wrZcFcCHASwiVfqcaE7ahteFQdaz+C/UvbfsytddzQ67WlP7p5eUlS/P22cNHbONSG+B97yiqAJ/OcK7lgJ7yw+YHDaamLl+DQQnPwRWodYC2rkAFfDQezUeAsQYMgY+1wNcD2hENg81mCYnABj5MQWi4A+7gD6F3dpXnTXiNgFJVlQqAEbHHnZgSXJQRRjbr3ogQxHvQKE/5dOuYKDJRG7fpianD442xtxZf3n67N7fmY1VXuewjbyxPX5y1W4/M2bblFUxOTwsuAA4H7B2pQjYxHrLbUR5CwIwAfgXgFaK1tQpmCLDR7gy+Qs9Dy3OcdlRXaCEMBBBrQAyWGUE5dpwB0Cf8ZLg9jxMb+U4RnyljiOloBpVK/4hBZtydRgkkB/BOAh84CUP/osFhHrzEWmU2WR+3ibHWc+MTE5cVXzz1Ua828kFzq9xfX1lOHDxsNy8v2AXzy10H3gQi/dAwLg84L35u11WO3fcFNoeqFIetMCdofmg9ac0A12YEAaB5JuTZMKQNM4StVR8J/FCG0FnyswDyzgfiDD48D0SQxkCeY+eRl/kY0GpwGhNQ+xqAIDwVYawJCCPPhlgXnFe1sbE5ZbVG865Wc9ubii8fu2p3VFvb9eysva9csQuWVsJmh5TVsVB34FWB0KdZiocg0FaBJubQdg5drrkiZja4fVc+Gh0mB+BFozaydoe2Azx1EQQHMwYTbRFGv2EOwGftrMwLIpAHSIQ5rqjHCeXI/qEOgJPT2MJUMfOSABCE4pgkdmbsDENMCCI8lLPtIzZT2XzBcvHM+5T8z6lFD1ax8GeXlLt0uLprbqGc6Oo4y4LrjYsU0GE4CyEWXsCTFwOu/YCe4i4EMeX23u08gunprIKZwf6HmQmwkzCUh2nKGu+nZUDXsAbAOxDBh4Ov/mMQAx0XNTnZJ8YJEuUwzHnABD3hqCOd8yKehRD5uXyo+cwCFGUoCBSqsEa1apPNiYV6pXZB8/bXP5B7WTUD+sv2O9axCV1AuQZ7I+IL1lwAhEoQz5rnGi/Q627/NXTF0WqfDaKt6xIoazl5rv1ij/qAH2sBNGg5gmCXhaZHHqHbe+W6qUoC4HQteYo3b0gRhe6GggiQgCyDOKRJxApyXqbJIRQ5jkiJr/UZeMojHiHxYRn1usK06NUnekX3d1T4S/Lucu/20QvLs3Svc/fCUjnW5cbMtT/GBdHAK+KzgBCwdcVQS5oPk3HIAmiEwMItkNF8AJXdD0AD7LXgU8YWFSFk4CMMYSE062lgHdXf2LDKTMMH0d/fsd5h8VzXCqCLtCGoVMADQYQ57ZmDvEgNAUeIAIgbCiHiGVjKwtYH2DmfMGbAqDCqYr6u+yTtiJabzeZ5zVsvf4gWBjOg37Zr6z0bq+gKExC9W42F4eBg3wFIYbb1mAs3Earhmq8KWQiUhdYjmFHwEQBlEYY5QusxP2GOfO9Pm6JhMXM97oi3o8dt4y+fbONvmLHKMUkAz7dt8Zb9duRjT1n3Rd0K1hlWBpyRAGiEGVBa9DYTZS7N5euHUA21XQm5ADxCyiMd/cVspg6mvKux1crGWKezfK0IWQ/Eg9wfXlCOb1yx7+pK+YyVbtv6vu1URyqFYBAqjhAwMzV5Lt+YBZ5WJwE2NAglg8zWM8APMxP2P7QfU6SyROszREzG7gGBhlDgsRT4jZMn7ej/+SqrndJyOIcghdnpPr5oL/zm/dZ+cl5CyDPBR8AoaEYuh5Fa/xMgcQF47idABWDcEOwh+KN5xBFA5PnWWYo0Xm1YtVp9ZIN1X1Xc9Y4lV/DjzXbp2vu0OKEGkHp4woz2hyRuThTnTh7gG/JufhQyE9D4DL5rtoDD5DSk0fVkdrDffg7QmuCha3/WeLS+k9YB2mJ2IAgd/tQWh8BismIzv7fLwecSsC9T1O9pyXOvuPJqp7Zsy++dZcWEoPITe9bOrIk5TQgwawEbLc/xoAObIdDER32mzXmkg/eg4yzFQbZnbS20Zb992pLVd4lIyofr2UWtqlUYOJdiAN2QqmffFJVuwB18FttqT1qtAXLQagjYpnwDYTlwofl1AeggUi8Byi4I+x6HMQCGJsD22ZGE42vAYMA6BLbbNnbVMVbbOW09Ac/DnPU8ZfWdU6I9WnUyAIAxCvR6YFGeAY5y7Deg5zCbltXAj9bJ4BPmvnMebWpHiZcgGkVRWSmXLlKmsJAT5ucTcjfTQ7u1t2SiMkifds5/MjcapG9BfdcTJgmzFOYCMOXVESDCfIAcaV8TPC+EFM8EKEvpVCe0LUDz+6eGFOPyGViUEpGPl5NtdD7Fs/4iqypluGyLzX/6aeUJRKeBCo+LEPKoTd5ImyRXpbMAoRmN53TOI1wbH00jjOi1X7YV6zvmtfLtZfW6x/o7ylKXV5rGEGW7jgCIMzrsPKzHTmUIPFOoEHAIAPCx43n1D2ADfNdw0cX6kPNibQhzg8BCaKMD8dvXo2rWOGVS4DMIeMQVMn8BJrqVQePQ3jh10mxGJxHtjgrtv1GPKFfgowB66uCyYIjnvGF7ud2XhvAxCjB1ch5hBjxmUq4PVaev3otyR/n2v6vWPv+Ebar1+lt7MimYFQYJ2OEQALFIw/TqBVnlyotFNINLh1mjY8FlNsQMCeD9ZlQMZhPEzgc/agbYh/mU1cPl2o6NVp8ZF28MLByL7ItiHvy2vPkULdLUF6eYIdFWdug4c+sBCQCAs64Tz2ODGrc2j/JRD81omjh8RAgm8BluFHjKX6pQ0CVOt849cWhTrdFuz2jB2tDXdK1rses7+KrMH7wp4oE+aNI1nuwEMlqLAADTTY6oYr8f9t23kaJxu+6CEF1amJkx1ONmdKgxsDccYF82c/x1M+wcrORBkDMDRd8O3f4DvyLZ9OaTcrYzWa1pv33BFpu75XnNEml/HgBsu0uN5KSPbJBQhJHicYSZH9Lwl8sz+KM0IYRsBXJdv6qgHZGCsco3tK2YqdX7vS0aWrMjAfAvprPoMo8KaT6SXlFxcgJ4zA/pEEIAylVDbCWZCaHd7GiyMGILGkIJRvOiFcxHjyy2GuyGik285hh1R59yCrDrK7PLtvK9/YpXrK342PiYLGWiEW3r/KNtbsOjVuo5BrM2jyBC6PB5kJSP5uU4+Rn8nJfThDlOWQgm1q9h2QB40cZY6Um4mDV7RbmlVut3NlYr2uNoG8gYg1k6DpYyY76g0YjzHNpOg7mDvAhnwB1sNBxBofEKYS7WBYQRbQx3DJnpPCgJQAeT2rlH29hJGwYmxkGTWZl//KB1nzmiZMUWnjhk47u2aYYESKVOymPb9bD8zGnrf/Og1AumMUOE0GQ3Gicv6q8fZr6gyfEcMhbyEULkoZjRDulRr6So/VleubJRr8OszIzpoTLaxgKpYUMhF1bYQzRLi0EIgXUAKsANAbj2k3aTEqAHwLQJ6LEwk+cCUnrIlN5hUd21zNI+5mfijSdYta45Kk0OJz5kB+e/9ayVC7p+kADmFN/8ym1qZsh7dUxm6PKtNnfXCz7YUeOZGlonoH72wBR8gcSQR6qNApo1G5o0C4TDKE20k8cIjtoWCPMV689Uxopeq6kKDYHSqHS1FeUBOaG88ri3r1c6CtueV1M+gMaNJiFlOkSRp5B4Ba/8qurgC5kkwlrKKxQWegVNbxHJIww8gog4h/ZSb3dVjm/Z1KXbrWwj8ICBKdheWLbF2/doXdBOSIqxePsz1l7UC0kqy/BRZ+rSbVbZJtPEm2AOTtbQ1QANyygPGmZr9DlKm8uH4dDkSMmEY1iEKKcsyof0WTCR32lpE1NuZVGMAxEn2NBS9ujYan9w4uXEA2BChFL3NOBSP4MtoD2OIABf+ZI1eZViRelR8BEAwK/1GrzMz+TVp1rjmInY/Tiymn06ls899Lz1Hz5gFe2E8P2HD9rcwy94mauXVIzdUGPrpE1ctV2HsjzLABMwRkHN8dX5zMAh7WhZxBH1ULMF9EDrKX854CkLJeO6R7unrXqIv7JLeiSNVYEAp1HGGiYIJtADKhLGdCMWVjXoYyHOZ4DMALQIRwJVvbwWBNNBE4zSWh5M9MFup3qctP+tp2uSiNYXV/WoPw6Kszc9ZpUlCXSMs7haXOjY7D9oP33Occ6XMsNpLZi+5hRbuvFJKw9KGfxMMFwHADGTRgWXso810jF+xh5CozfigQd5Q+CDZji+LNjcJnXIC9flMFZ2d/Ha487SlgTUipsTtNU9afdodjIvDmieBZRTlumWBTJaHnmVYlntoP3MiBXl65ZS8TA7zARmR2i+52s25ZlQdlds6l27rH6sDl9dKYSPQYPXkXthz0FbueVJrQuoTRzlq3qzd/mWp2zxmUOi0QIheuqwGNePm7LJXzzdZ0EoUgYCDcwgEeb8nDeaJp61emjOhuBTh3VuWDacZdSN/KFwdL2ivF7Z26n7n85xVQmgLuDqAgobHzYfoMN2h1Cw6QE6gFYB2EPFk9AwMS4EgFd7tQrtAT6Ay0bLE2bgAbwQXSHwI0+2f0Vbytcdb1PXnKmFl0usjKaGJGwPfVbX6PvmdHHFMwJtf6XQrAW2d94O3rjbaQJ9abfqlnqpYMPbT7Pmebof0juUq03LemC/VBhhy3O+BLGurV/bVghttSDCYiDMnjYYpXWO0ziWx7HPo/YdEAEXoL2sEmA66AKwknwIQZovuhDGsuiXJcAVLeoRh5a3vwN4gY8wHPSIuxB8Joih3pJVNjdt03svskK3e1yFoM3C2U+080/ut8UbHpLdR/s58IXnzMGMWLjuEZt/UqffNAuoy91RoR3R5t881yrT2m5rQQ7Do8JVM2AIcOSHxsdimcEdNTmjsyKDTTikJT6sH/35BkMCYDZqlzdeYY+ewY9dDMIIDQ6NBnAAFDgCr1IQJu1XPsDHzMkCI0QomKSlVE/1HXi0Hx/mKBZkPXuWwMs+gurZlt+6zGpnzFiP12EkANdiaTJDO/SJe8yenzW9Qa72fUlQH2kmYI+e1yz41P3W4/4E7cerDdqqn7VJbb9GeWpJJ/5oMYMFOEPwMBWj5sKBZH0cLLQBbIA7rDcEn7zssxAC9Jzvl4w6/GpPARjSEtRMHXMlwdZO9inSKoPZ0akbO4CYTrH3l/1TPZ+ars3EsXuhVTEY4tFH5BPHKQQoPXDZ9G+vsOZPnWE9tpQjxUWzZoe/+YQtf/5Bq+puHO33O6jEM7TMhr7WgiWZodlLT7GNr9H2VcDnLvqLHRu/6mTbvG/BDv7pt6zSkBRZj/2DxRVHp5nPiA/egBgpG44nxjdaj7K8tqymg5Yytet/rG3aWcrQqnMKYYUtaDTgA0IYknyuCF1uFIChj0s05WvtCObJz4zlMA+M+s4C3cnBidK6u9/47jfaxK+81rrLK2F6gkCmRwbx0IId+uOvWqGyakPPggW2e+9HohB6CIRNTl+7owN/fJe1Pjxj9YmmmyDvSf30lts29e6z1F/HDv/fe2TmVEFnh9jZJH7gSX4IPGMI/vPYI00e2EQZYwePGF2Mk/IsjIxh0CNucJYAdIxxoqzVVKAhT49MudzBMIwZ4N8iET2dUY/yPM3oDKajzRiYCpWHE6tcLwuATf/up6117QUyFZgi6ienMsoP/Plt1n1IB6+xZmi+8yg+oyG/saV1N0daOzoP7LX9f/5t2/qbF6ubYXusB92Vjk3/m3OsMl63w3/2DbhwIQcwwWO0m4EPgENI5I36KBvNy3QBPHgETQgm2oeech7OaAYsOkhURCKjjWXtphG/22AwaUasr+VrtT8E4MJUy76aqi3+2JHUtmywDf/hbda44kzrLi7rsSIMDl11vGGHrrvb5v/+m1Zp6qzimg/wtAuv4ZADL8RimnyIMlNzf3+vjZ+yxTZds9N6mhXZceXSVT+Tv7LTatsm7OD/+Jr1Ds6r/Zq3OyoIH7cDTqvrAR/5wYv37HSBY5QFR9TN5YQkBzNgQUVoLy60PzpTngY6iDNgJ8LUkJ9NDnH28EEb2h4dIqQAizKcQh2y2NuPX7jLpn79Z604cbN15pekDdDgg5OKwF+8/Xt28I++IPPGusTXhDCJHBppF9ORBqZ4RXYIU8Qz6pJ7K4G8/3/dbo2jJq114YlumuAAx/PkztySNa840Y45dbMd/vDXbenOJ/VIUL3zTUHxMWg7jStwgL8MJiF4AWSmD80OCxD5MaY8tlyXtHCQEIrdO/+gbNVb0iBIIcjAIpTcIdqGzx2ttm3Z5GR613jXUtEjREDhLr+rKXfS8Tbxrp+0xk++Wgu9Fn3fm6vpEVcdb9ryNx+zvf/1E9aTcKo1vUlQ1OTr0vKq2mTLw1uggIX1R2iCQhKAs57MGBejPU7UGybsuA9cZc1zt0kI7LgYU9yLYmpYjGlz6UuP2tzH77bOUy/62wcVF8QoYAF4AArw9ERb9E4s4xZ0lISwckhOtAe3XEUsdRYkgLM+UE40xkYEANAQrgY8Os7aP5R0Bh362AUBuqrDGNs97W7IqJ98grXeeqk1rtRWcKqpnQ5vB8B4sFoKPOrVWmO2fOdu2/eBj1tXWlrRF+MceASgfxWFgB6ejkIYDoPa8OFL4N3kEUJ9Q8u2/e6bbeyC7W6OYrbBljOqb0HKfLWaeomzY8v/oLPEZ++19lMvaAgak+6adOEqlwEEfLgOoCOeMcu4QJt9gJ7BpyXqIIDFtgvgP0kAeoQ3Ym4gZihD26ZGfEEOzfe9dFqg/RXBVJc4B52Cx5rcVB610Rrn7LDmpedb/dxXWKlBOvAqd/b4SI7DU02L7NKX7rYXPvx3WhN0rVGX5vPPtV822sHWDPAQ8HwzqnAYF+4ODXdGCIEQIdT0wGbrb7zJJn5mh3VWLfZpNtCKdlw18Vjobmnl7j22dMtuW7nvB9bbr+9l8WoM7+dw6k6zm54w39Ej8Qx6DkNIUZ7zglsEsNDW+0u7z3pvOSkB8ALpwJQI3KRLapJGRjpxkzLM83IxZx1dJ0y2rH7CsdbYdZo1zt2pByKnWLGZV0l06tMWkB2O6zy8ZKd4pSmgO7pk++gX7MDfflk0Mi68wJS0npDdf2i9n4FTfNQEDeMIAY4dfBeCnvRptsH60W+/wDa9WzsuvVTX045o4MDV/ymUMuibLeJBfR1ctM7Dz9ny3U9Y+4GnrbvnBV3+6YDJN8t9ZgTIAT5xXOStBT6nQRoBzK9IAI/u/DUJYEKLnLKVOQA77XZiKilfQmHRCImDIF75epOusnmTTVzzk9a8+DyrHKvXR/Q92r7ernb7DuggQo0IPM4Ht5O1sXHrPfIDO/gnn7S57+7WlNdW0wHXF6aT9ksvBU02NdJ6nsgozXEsUBiCD4wIUHgPZkIIgkOmYNJr91PnnGxH//srrPaKo+LckR/2IwR4BCEPUARdeTckDD0UMt1N9Z49bCt37La56+6w7kFd/slEBRZUxAP+aJjzR8MQwMLKnBXf33ltOdmc9DUgwA+wY7uZG4oFJxZU2XUYlLBKvbFQP+VE2/C777XipOOk5bLrWmhDUKJJjlacJ08LHjSs1bLiyILN33CzHbr+S9bVYlvodwwqvB7j0LPght0veLDuPpucEEKch/PMAAgYCwEgBASOSgF8V8qDIHxEOojVJ1o287bX2fTPncs3KKy7JN4RRAIfViMaJsrTUtJCD/zZJPSf2G+HPvBJW358T6wTLrmMVxYC6VFPK6ThqRsz4Ps73yEBTIQA8n0H9j3ZeA+JA/hgaqkRbOKGSdvwgf+irSTg6wTrTOQuvB//oEuHRpc41bEx2dglW/jq1232+s/b8h79LIOAZ2ejHwwYgO4LrvaFCCTAl8Z7XOBzLSox+QxQXggi8lJPykuCgFU4dyGwJmgmKO0bAJ3Ax084yjbLLE1eoRPyVEOnZT0oZMe2xmW5pHVbzyJkw546YC++78+tr+9ysVDHtp3RrvUIBJfzEYBMkL6MUSt1SVYyeJQMADE9HiIE15+oi3AQQDJT/Z5uO698s9mJ28S0TtPetgaWOfVaTGFB2ZRmS+v7e/fZ4h132uw/3morP9gjXBtWtOTVLi9ZVfy7BIoLXGD1TQANJ74L7AppVwgEk0GHeQaZhKKaai04EGIufE9JVBobM6Gvs0JfvxSyvO8Fe+4Pr7fxz9xpG7U1bl26wxrH6fdFdGBjjYiXwYIFmog5JOFqF1c5cZN2da+2pU/eLCXSmVbtDoUA9SjwUXt1S7xFWNFdENeLGoOfdl3z0yCJe5pQwmDwmtTsgnp6mlk/50zr69EhzIaDAWymAK/XVVXadvCAtb/9oC3cdYct3v+g9Y7Maq8p7dFVQMDFo8vQd3+4r364zMznB9d+512ZEiIX/gU/r6K2XQDMBgburWnzIEH6zEhCgGO1pj4QRMzhCFnNNBe0qyll55ef22v7PnKj1T71FZt41ak29Yad1ty13SpbprybnjYZfQTiGMCgupUpq77qZOtfpzVKGMS2lh4BPnqOcDQOPxKjt8MDJV09m+7v3QZlwHPoDWXwCSPO64K9ySkrNk5LQ9hJJAFokD19u6/70D3W2f2gLX9/t7X3aOcA6MwyAV/oLWAY4BGomxzVGQCvEtdb+MWTgFE8QDNNmZ3MBAna3+BDWmg/5XhVYkYhkogLYEhIx58CCUJj4bVLKEMQopEguiuLdvhr37HDt3/HajrENU882lqvONEaO0+yyhnHajbrMajqqUn3+jKwlFHKNMeDJWc4lWQKwuxG49TnxeUq4OsMTt1sgrIE0XpAB2AGKhPh7CKA6pK2dtpa8mTHp39ooZsp0fp1gN6wKOVND/CjDc0O9QMAbKcRQpgaDlhhKhwt+HX+9eG2kVAVHUkaIC6ftZ94NpvYwCSIMEugTtsKaUZNs+FjJPzTy1EuiFjh2CnFGIMBxi4q9evvxqo+a4eXIQS141tsf7oVLYo8Zq+oog3ocYT0nkPyfAZo/55nAMA74LSiOOC5EEIQpeLONvmajp0De7WxPlptos0KZJoKbdcqZ51jk+ecb3otysrDB6396EO2+I3bbPmh+8z0ax9VfYG5opfBsMfCxus6X/rwHY+zJh608/Gp6jsg8ZMFAOAOOqEacEFI810wEq8UpfA8lam8EC3DDkF44wkKlCZmQUUHSMwMG4vxc3Za6yKZoB3brdiid0yRdTZBHDJplgY1ITsvHNL7Sdwo8y8pkWJDt14cSsYtG8DzWNMjx0AiCQDwBwJQnBmQNIzmkLW1l235wW/a1JlnqxnP8T79RlMPQrpamB1cLcD1815vm197sZUv7rWVb99uS1+/xXp7npVya/dTk/fRqM00k4YhAgFkte9CgAY05PPMQADw6nTQAriQYcbyFjLlqg8JZTH0WCVKGNS2udCup7H9WJu4/DxrXqQveBw7rWyNYUXrmxTGlUC0Dpqj70N1mJfueVjKqMtEHSbFSPLq+yWOPMqTS1GtAQhAgd6rH+yCpEGDHZAIPV9jczOlgEGUMludu//ROhdcamMnnKa3DvRrTd6B2qEveWdDe+uunkaxh6pMbrCxn3mH3lh7s7W/dZst3fQ56z77rC6/xiUsBpAqammKqNJJk/3KA03uAy7MiEfi9DkwT1kQKQQ0F4DqMWA1NxAEizhfezr+WGtdfYk1Lt5p/Za+TKXzANvKfJbxMVDRB6U2GLs+Ob0vP/6stb96t2Y0/AQlFOHWpsnNeQl95RSPvf6MclL3H9U6WgyBGINLJO22nAGqaigXpQJTz/PxHMSOP9m2/uvftspxp2rbJo3RVHWNEZ1XjOo04UlYZc/PQayiH6No3/ZFW7zp89bT2aAiQVifR4V0JnC90xwqz4VBODwTOA2aMTIDXFMceBjPzKtjMc8kK5e1e2npmvotl1njp863/mRdwC/5NXVAFEiIMv1FLrucSk0ndJ1l+k/ts70f+ivfTte14+NXUrjOYS0buqjnAx9kUi6bIUbmtGEpHr/45HJCe3G+FeNA0ymKpZUqg54FEOWataLJt41dAV6f3mib3/gWmzjnIl1LbBN2uoqQdvX0+2XxhAtGpI3eRTDIJ2eD6viE2bNP2OJ1f2Xt7z0ok9RSiTYFgB2MCAQxJHMyKoAMeD6cDZjNgnBmVYd0jsuSllq7mmftsNY7r7LyRF1FLAp4ZoOcwy5WHTZpvHOtnRGPQatsq/WSWH/fQa1n99mBL95ibf2SSU3fyKwLK35Bi/1XjJHWGGGM29sjC2VwASGAMk7Cj1+yvZyY0HW0ppHzmpUp805F8mhPjlDj8FnAkyUE4b+cxV3/xLiNHXu8jZ96lrVOP0d29XRtOzdqcdM1gNaMPDOiKWwqxkxao/sfvuTXvvkztnDz55TDLEAISfsRRDJFHuaZAMMj8bD3aA/MJ59mh7+eIiQm3vwma7zlUs1gLghjtrp1UVkAJZ6kGJxlaroKt9kFaz/2tC3c+z1b+t7jtvLsXl1pa31js6HzCFof2q866pLxhMthpGLtIS98CEDtPPbGE5MABIfKXIESXVYemnABUC6PvuDjujeE4YPQEHjkF9fRFWts2mITp+20yVdeaM2Tzxae41qcEYQWRRpNzruTWarrYq5/79d10fVRK/XwpNBOKRhCAAgjM5C0JIM/Mjt8ec2DSAPgYVBlXK86vvPtVpx/dnr8ycIeqHuoAbGL4qqkqku39oOP6/D4XVv43iPa7R3wmcw5wV9vFBsAjdFA86tovwTh49AngiS+GvScFu8qRQAL+vG94rErTyzHmQF6sclBpmLQrAKdFqM86HzMaoRtceyhVR7jid7Vjp9W9ZYzrxSObz3BNr7uSps4+xK9PjKVBBEsQgrDfNbGdEn3xAM2+6n/Y+WsNKSiByUOaBYC4CdmyB+dGaNpxZkRPP6sTm2wqV/9V9Y//RRpbzz+dF5BSh6rUGsKg/kVW/raPXbkK1+z5T3PqUhSkc0XE0Eo/qAlBeCYnAw+eTjEMDqqLIQcRm0EYBKAxvfoVSeVE7rd42HDQACgkcdInPWA1lMvTke5svA0FrMiLV4qIy9KCVWf/bP22uPHHGebL7naxs66RA/HxYgE5JJz1qEFDJ0T9jxsRz7xR1bO85KXhOBAIwQx4Qs0DMAQneHJx0d+qTzAZ+c1/Z5ftf5J2+PqWXxlzacvrkzqqrNyh4D/wlds6Zm9akLt4BmDmgNUBRE68EASAgjNz6W0iAMv8tSGXI7nkHxmwKLMcvHI1RKA3p/hCRb9Of/entLRrjMxGve2+Yj2o16uywD9nzDxeIwj238dHVXQs+nTX2lbrninlZu3a/e0HERwK0e3VQmheOK7duTv/rcVK5gs7pYwQ+p0IARAwquGe8oi7neG+o3P6V9+j/VPO01XJDJ9ahfN94harOmMUjz3gh359PU2f99DaorDHH2IhqMPZom4aOEpg+27Ic+L/OAYCjwu4hlwwjh5iD8viwPmojYpxSPXnFy2EIBruaCTZDPYWcGGbarD3I8iPjOH/cW4lM5jJETSeYYgBABwrwc5jYlpO+pNv6QT54V6rjPcvsagNRNkj8v7brUjn/+oZK2zijS/KGUSJAg/6TrY2TTBWAjDt5p6B2jqbdeanXt+MncwNgSorp1N9+7v2IFPXxd3VVpwA3Bptnj0cydCIM70FnDxL2L+OQTDy30T4ABnkGQGlQb8oQAQQpjHRb6CVcr0oFicbZxYdbMA6NYRV56DDeip7UhTTKFTuvCiTkqrRbfDSoYgdFknabhgdDHX6Szavi/+hW0+vE9fxLtak0Ml2hJSjusu84X+i621f48tfPNm7dR0mafyimaAn4wVkvYrkBEzxKLbuvgKK171KrUxvCp3RsVvTbuXpZu+YIf/4SZ1p1HrWjr/pl08EEIIjFVlMCNBYGMRgAOwGiDHzUsFSggBkHFITuCucRgvsOZfjetYbHyfGeC9JWpAzYCrPQeaUHS4LJDM0yD0iJMkxmJW+c2jBuM3BBq0P50CSAF44M4bNQOWbPqCn5MFEVGaKQygo2fF9Quusvpzj1ln7w/cZvu+nXunnhhCe+QxH2gOX02qnXSy1S65wrqdkZe9AFLj4eJ7/kvX2+wtX5HZ1W08OxvhpIuAZNe5JRUpAmC8YAhPEgIz102e2gFAj1Os1OBTZR4nC5pVbnWaXRePoKJNdeYu2gqgYQDA+aOu4hn41E8qCxrvDzoKU1ZImpaRtyaiBsT7O/yUsT+rdXvesCP33qy1tWbT5791cHjzAUtAPZ2Qmxf/rLVv/BMt5moAPgCbkzoXgVpTdK3pvtShsnnFVdbVA5K+TuoxnYOnQlcu8//4OZu7/SbjhV9+z457qKqY8gdCgK7xO/iKuwIriMFwn0Qf6p8yzJ2IVwuC2QuQogGokBgNrOOg06maQwftOaBEaBdPhoSTBeCAMvDcN4LB0Q6FhGS5T2WwpwquDCqSrnk8rnbVFtNfngOdjps2e//NVkzpR09foYs7f86gMaie7IiuOk7XnfxrbfmBrwkwmSLe+4dPEfjjRf3cCw9Mmue8zsoTtutuCtMTDKknaXvdFu+53ebv+KLA1yFK4FcEqFaTAB8ateV3R8JvIDhnQO0wLRAyDnwzuCyULgiFisuWxBgV86pRY+QToKCTEgobrWyqn9oFROKA7po+EjpdTkOPADxU3BtQd8rzMXsWhQlwoiPONUzsxWAZmGaDhMBPz8x+50arbNIF2TGnSAi8CKZxiaSveOPsN9jK0/frkKYfHuQCDGVklHoNzk+6GzdY/dUXiZYdDygCigKtHUtPP2ILt35GgtYzCPHDjwpqOdeNuw5RYjp4CSH4wFRPHHofIot2fMCKM17WK3XOOhFvaUCUB0qneHZv2HtcLsvxEASWU68jqFBrgQNPyLqRQraneH2XSXmRr3nj8bx++E5QNIwshEc8tTGop7TinDcKHfp4B5PDX01vM9d451+hv7Mv8Ga/e6N+Bl+/Do6JkfGVEdJiqSdO03rl/IzXaL2SlnFw5N2cFPb0jKK667W6zz9KM0JnCwTgN7096ywdstnb/1ZXIofVtzS/psu4ugRR0wm5IROmdKGHRkVV9fheg9dTvucpnZ+LEGqmhVfcFwiBrOckaH6kEVtArgzxkYWhqDvy5IW5HsXqB5uK4lneCeL1vNB6lSfQAd7NUBbICPCAH+URZloXTgaaQ6R7gQvgyh94AedxhVW9W4MgXAi8U3TwKZt95GvOpA9Mg0OjeRTaOO08syk9CmXVVHu+K9VL9ob2n3GetF/PbqXdCM6vlKUIs/fdZr3nH4vdTl3PoOUB2wHnaV1N14s1Pd3zuNYNzRJ/igfg8v7dhxT3RWwgCMqZaQgBbc9CAXTyCB1uD0djGq14rDxbqzSKB2u14ieY7A6iGMZuuzAAmfmKNsuXxPlLoQtYaZ/T5K8to1vKvRLh0Hm2+PM6zq9ymNa+yNb1s2PfsKXtu6y1YUaKJUA13bH1laktVt2ub9E8fo/4kWZo/OykqifuUNnmOFmrKZpkfVs6uE+/KXGnhKvntuLbdzsyOf4zPGpPslKfmS+EBrfwIq/6ft4ABxjVmjEwbb4AqSLAAQ7teE1mLb1nT/5oXO2ILq4wygelhJUHaq7NyheD2QzlWTAwO6IZ5CWBIDBMStbqwbuT0Cof+pgRaltpL09hmCINUDODuH/tVCYlTJEWyd6czT/1LY2LKS0tlIah1SBW375T5kcPxzHiqlvqNcLaSbu8LJAAUdFLA+cf/YaeWB3RayNqU7T+5e5kuoInVVM7pS4+y7qAkokpqxIEs0KzhFlRYpay1rMYo/X+qBZ69UWe+oJH75+4g05aZS9xGqf+aRv6QE0PtvbCmC+MCVgE6lqO6RGGXL0QogTDMtUh7XkURpmHnk85EZgjlFPgsWEy8acMkbE1rfJkjpmg6+ju8w/Y0tx51tLOyC/2ICv19dlNx+udUz2L1gHOF/1NW62+RS+Hue2nrv7U5+KRF63z9H06UeuUqzQWwbeSChkHnisLn+3CytcyeANAx1K8ADSz0g96Ao33Rb0ChDgaSeUKfcwKYztKOZ2pyVUxKYLa0L+9tV61sohpYa2GATcnmTlMjeJDM6RBrEl7y7QOLX8p9HxlO/iUZyEQlQ+2FJEjjUORmPo8VMe8VDrztrTvYRufvlBEGpzKMREVvid27E9Yb1YvBWjsVcULvUntF3tqwttXf0vPPKjH3bN6fMhrjrSvEtH7mw0KiQOYpxEEcZG4IKQEruQ0po59l8WskrnTPliZLG4K4NlxckK1ScNkZq+o4qSGLmi1TV6s1RuF/osmipRJPm0r7Q+sMTEpz81NEshASF4WQskC8DaoRBmBN6DuSXsGYUpGdPiJbZYU+DYMb64xTTv7H7Huya/WrTBMUZHBaPc0s906T/HQRj+8c9R2FQhBJaJrffdeJ+v2vt0yaRKk+JahcwGi2cwCB51vccAX2o10wU4OJUIInMqxPM668n22caurmRqYiScWFRzm1gm8QVVSY2iLNxomKSjFh/7BrX6Ean+tXtQOe//qMD98Hyy2tKU+YgYoofgAfDHpMxGhQIfgNHrHO1CIfMo8neiUXM85mQrgudQsqEoDmQXFyn5bnt1nUzPHqSwGxW6oOjWjh+hTqiFaLcyYJgeRUareyhHNjgX9VA0nXh+yigGYcl/sk7aj6TLxgBJXMYqNgq4KVPEhgBqM6prbbxjZkubbUyQGFhKCn8zdnKgmgo0/VRw67saknIdrvVrvgB6trQjMpk9BgJTPoNO+x5Gwg0yfxFPa8yLt4A/SakfZcE4QHyMheWud84v2MQsYCz/z0baVQ0/a5Mw2tQECchJEVd/qKaa152fW6PGh/7qWd0Q9ffv5xSeYP353lNh2AbgQROdbRMyd4u41G3y2AhjtuBCG5Rz2cBSxJsZJGAEoQ2uoTxkXAIyDOPRZ4sSZBThZfoGtnBXd7B6oWbOxX8fyI8o7GnKoAkgBx+IM9zSctN/Bp6UkAC+nQqZT6PX5gA6nuOd53HOGZfA24kiyyQBEvgSOGWrPP6P3dHR167Y3KjCc1rZTRU0n5Dn3Xq8n2t6RPTpbDM0P7HF94XNfca8GiwKa2q7nruG5PQpV0hXvmBnx05cQvB2nV5abMPXrOySVcK/la4DmnHj3Npm14o1Wc0/MSLV0RL+4ur+29cxTDr24+/G9+sGLo7tUhlLthM1XPGn+QOsRBGhCk2cBNPylfBIhGNqiweSIjiTJJQkA2XmxMtjiVzR4XtwtOoess6w3ECY3ChPd+YgYjW9t2+GVV/TtG7qJpvXF7iX9lFn7kGaGBCCe/J/sNvyi7U5II67tKk0h+b4D8xrAp4y01jqtKuf9Dc1wNqGqC5/tKLbcV3BlYtoYmWiiJQhVTpNa42T19m496cxDleIdn+7pxaLdWgwcLJh08JPGZ2G4IFJelNOSvMAf1kl1aQuhDISnfplNeOjxivv2N4WjZwm/IiZfJ2Q/QevVyfbC8w6YH4TcSPdtRZdv+KFtEapSjPbcPgW6wON6gzbEj3/ZztuMvv38wIxSHt5/dT3zrHH6NYuPl7iwc1wUKu4XuOSJ3k/k8OOzQCBj4/y6QnG2dWo+BEzo7On2RIph1d3Fp9/R4ygDk98SLz9fpKteBuEqlToZAImawSTlgEjoreZ4qqd8UXkbFLsbhIoQxyelGA09W/W5qWQ7ir3kd0Y7R56w/tEnK61KrlXRLCqo3iOhgAu97iHZf43Mv15EV9Jct9mcWkXjPGFu6JgTr7tohzIU2VXbCXP7aUZAS//wLnz8Eo+EY6cOdE5QC+79bT6EwK6JvkSHMHiNRXeA31KmXwhqp1D9ervT7UvbNG4RAjTgInUPI74a/KAJM6Q4TAM89Oogwoh7mQ9G6eygfxkHC7QVT6d4QMLXGJ7Rl6t/YGMbT5KZ4PJMNGlcTHWaK3SqbGvBtvmntUirDnzgRZcXX39WnNil+2ySaMpNhgRC00DoJoYZovajB1FBiOYTYfckvNkIDBZltN+lo3LfotKS6DwPSPUbMXqo0aw0vk6+z4Dprj1wpFr5fqNWnrGidSDOADSuzhGoTz/FfQakfAbhafKJ08sI8JQp7Y4gRT2PImXBUyZhXE5CJDnXBTVO0/xswsreb1hrclxfOT1WT9D4D4YYLG3oXKC3G8p5vfz77F1+muatuxCAKoOBa3z05114veiIdGbPG6RMoGJenBYc0F6kBR4wzp8Yoxw+OVc4yH5NoQ5hWqXerhOISDQNJGaV74/bFv9vTJys+K27lmpj1RvG9MNGYc/VaIxatAIVBpT2m03i/LlwFFF7btOdTm3nfJClDaW9nDDd+3hd7G7yYYMTHRontaAvXpf0H2dSPX66sqcfdDr8+FesO3uvHugv6oSsn6aUb07ouwqHv2sHv3+zvhOs/waYBy6y+3ldyWuN23v49T7gHR7gH0wEl8Kw/fBCvjI1Lt/Si9bDNCZXRsXzuutp1xiBz4LMlMP8yIMlviKBjuvhf71auaG467d4mzlmABG93/gxLWe/oQV5jC8t5M7CxIhADOROs9lxxhlEBnsQil7xPCtcDVSdYnceQXfkoCP0KUoMrWGUMK8/xqNUX41xQOzpwcxB3YTW9jygt9j0I90i6+olX37sgwoIqiY6Z5eW6EaaR+B8pu2h96ruPF9l4ZJpSZmu0QiFQj48TqUA1TtRHNbBImZBYpgKbHthQHgim6pA7Vb7y7r+/1j0p6IcIVz66MWf0CXAL87ya1WUgAMjAWQPVUGD87TKctxbId/riNZD1QVc2iDNB6HHSSvqhMTEnf5Gy3IWg+NtiZ5On11Ced5k8KsEzKXK3VyoOmPlXc3wkQZ83+tDqH07a4D/wq7y85M0P2QNytSm4r7Hx2ypP7amkRdp6GnT66XQryzYkHVkRfp6naava5Ieb/XxeqXeupPfUNOX/4rWJ5s3f/iXVNudrwE5MVYrPtguqlfr19QneO/Tt19JAI4fIMs7qC4I1XSAE7gIymkSliNlA7DXCkFNaDhrsY+0MEIQsMDdvj8H1uARALsdPxYBpP5olu6yANwaADq7KTQQoDA9FECsBVQxj0LmCX3ErkZJJ9MHYWoDqwCncSOi3mEMQuWTF7iIL97Y0AsALOJRX48/oa1XFhqNygfV28DB88AV77r9gVqj9qENG/TQGzDxAA7fNKA/H+WoEFJe0AYTrti0rAhMDYTicc+OdrOwaDvFaT8LmGntBzKV8yUI/XfiVtfe3r0eY+Z4QwcufF22nydr2fYjObflA5svntTmwHTCI2nKCX0sxKmXeCL0OqQZkzzrhvgdWAniKgvvEhOBhKkdEV+9hZ8NLb1u2ax8qPjshwb/h5haGq4BJHCV6drv95aKN05P2wWzen3bpZvBgTHFHaDMoBhygL1MDcBgAj4k50maTmU5ktJUiD/0zzUGCneM0P80KNY0b1eDlWb5BihpmGsZ41YlvO+7RZ8zVMMTkDMBPKUE/UHv203x7+VKQ+E3CADuxKIiDsjep9JsMSmDR2xfEoALl3zN0HhMaTat6/Nes3JXdWzi91WyytH/S1z5pZ86Q8eZW1aWO9sW+eXa0cYRQAZf+UPtVlO0lgVEmFsnJBF/QTcopOwlLEQGA5HLU9njAAt4KsPHhxpQAnA9LRoHUObJrxYwU+QlWz6w60prUx5rgkyb5xPKY/Oz9/UgpzFl1HM6sQ7QHPA8rUtE7o662oX19bqnfEtvgjfHZp4rqtOXF3/zJ4+IcpV7uaFbectPv0Ec37C82N64pP+dwu2fAA9ToWoZfKanwCbt4NNiBj+B7sCPxDMHg3UhZ7xM6ALIZRq7L8CkARU11N/AAzppQoSVhQBo0AOk4oRrAQ/gRQQNawTXzhIQ9TxUPmtPFoADPyIAf3KpehW9qVfp1vVfVk3Z+OSWw/pf5362+Mu/vE2tvMQB18u68o63XCkuPtVeWNm0yE9ACuz8rMAF4GZHTdDKSNyVOwHu5irHsxByj+v0TpaGOHQ5kUPKXf2JQJaATnkOvvJdSAANTQLdTVMCP3ZDQlYaDdAlQCMUB38Yrj8LKFe7LgwBrjpZGOyGKt2KTVZbNtaaOWS16V8oPqLf4HkZtw4EqynL71zzBr3j9/FyqX3c3DyvbohhaiWtHyyYozMAoJkhKaRFj1Mv+xT1dLL10IXTAL0TUgIxgkGRRyBxdJUSjkOhqMDTynPTo/oOMvnyDpo0OYOdBDIAXl+n8tnhM0B1E50/hAF0pb1uagdBBOgamrdvtllf9qg1p5+16qZ3Fn90/W3B+PqfwPFPuvKRt+lnpvp/ofP/hUuHlhTVQLLZoYVR8MnnL4cIAUfgfs3akMsIcWo6hOKp4Qf5ckOgIw19FkQADpETrjJBLoQMGqDj3f4zCwLoAdgj64LPgJHZMaBVnTgLiF0JmCsgvuixaUrf9Kw179B9yXuKD355d+LyZYOEzsuWDwrKfddO2OLy7+g34H6jWGlPLs+txDudCfwhwKoyCn4C3uXAR+5xbTjoSZEE9oA2p6FxcBPoOV+D9yI3QwKTtHvFReMLcQZdoc+CEU12kNH0UeA1EwJs1SeeTU6eEbRPXCHAb+Q3TcfG5iu15oetVflg8R+/vOo/bnYG1/nIMKxTtH5Weejdr7SV5d8uV9rXFN3OeF+CaPP1TchpTeBnu++WhTz3+iDErQ0jd/1PjXGVG0m75tMxeZ6vD/6YoTlUOekQguLYe4SAidEV8gB8gTnQdoSF1uOJJ+FkwbErQuubelFgkh9vqjeWarXGDdZo/rfi1z9/3yp+/4lEhuKfIHtpcVn+2i796tw7rd25Wr8Ht0OPD/VFK42K7wczSA0aHNw8UX097X9psz96Dm3jCRLgnnaVVx4htp8yeWaFm50EtAObwA0NTwJIYDvoDnQssNyt1aVZTX5mTV/ca+uqVF/Q3q3vGHzOmuMfL375M/cHN/+8zx9bALmb58r3t2bs+bPr/f7rZZNeo4e3O3RK0re1+9MauZ6ci1K7J3ecnvg1Kqa03+OAIAQ5DLLBDEnJCNZhFZBxBO5H0gCewHcBoPUIxEGHDwFOXtJyf1VdSuIXgUxdTI7K+OqBtqTLOovP6jrkOYX6Ybvqt3VPc4cdvfX+4vUf8ltN2Phx3Dqj+nGaGda5tXx/7Txb2aSz34y+3zKjd9I2qHRG50x9Bb62VQPUO4S2U1PjOOWNhQBgI3sWFRzpHM9hpnGCNR8ugZSX44QCG+n4wpBCnw6hBH6k7usXzHvGk/+H9MN8eh2vr29j60e1rdCrdaaH0Y39Mq0HvvoTWw5dVrwf0fyLuf8HvFb8ZUfezBYAAAAASUVORK5CYII=";

    // First path segments that belong to the web: sign-in and consent flows,
    // Instagram's own link redirector, and its static and developer pages.
    var WEB_ONLY = [
        "accounts", "oauth", "challenge", "linkshim", "legal", "api", "developer",
        "emails", "session", "web", "about", "press", "privacy", "terms", "static"
    ];

    var handedOff = false;  // this page already offered the app once
    var dismissed = false;  // the user chose to stay in Safari
    var ready = false;      // settings have been read

    // Set from the extension's popup. Keys match popup.js.
    var settings = { banner: true, auto: true };
    var host = null;        // banner host element
    var pathLabel = null;   // banner line showing the current address

    try {
        dismissed = window.sessionStorage.getItem(DISMISS_KEY) === "1";
    } catch (e) { /* storage throws in private browsing */ }

    function text(key, fallback) {
        try {
            var message = browser.i18n.getMessage(key);
            if (message) return message;
        } catch (e) { /* i18n unavailable */ }
        return fallback;
    }

    function isRedirectable() {
        var name = window.location.hostname.replace(/^www\./, "");
        if (name !== "instagram.com" && name !== "ig.me" && name !== "instagr.am") return false;

        var first = window.location.pathname.split("/").filter(Boolean)[0] || "";
        if (WEB_ONLY.indexOf(first.toLowerCase()) !== -1) return false;

        // Outbound link redirector: https://l.instagram.com/?u=<destination>
        if (first === "" && new URLSearchParams(window.location.search).has("u")) return false;

        return true;
    }

    // Whether Safari would follow a custom scheme right now. `event` is the
    // gesture being handled, if any.
    function canHandOff(event) {
        var activation = navigator.userActivation;
        if (activation) return activation.isActive === true;
        // Before Safari 16.4 there is nothing to ask; a click always counts.
        return !!event && event.type === "click" && event.isTrusted;
    }

    // `explicit` is the banner's Open button, which always tries again.
    // Otherwise a page gets a single hand-off: Instagram's site moves between
    // posts and stories without loading a new document, and asking again on
    // each of those would make the site unusable for anyone who stays.
    function openInApp(explicit, event, onLoad) {
        if (dismissed || !isRedirectable()) return;
        if (!explicit) {
            if (handedOff || !ready || !settings.auto) return;
            // Past the load, wait for a gesture Safari will honour: an attempt
            // outside one raises an error alert, and a swipe would raise it
            // every time.
            if (!onLoad && !canHandOff(event)) return;
        }
        handedOff = true;

        window.location.href = APP_SCHEME + "://redirect?url=" + encodeURIComponent(window.location.href);
    }

    function dismiss() {
        dismissed = true;
        try { window.sessionStorage.setItem(DISMISS_KEY, "1"); } catch (e) { /* ignored */ }
        if (!host) return;

        var node = host;
        host = null;
        pathLabel = null;
        node.classList.remove("shown");
        setTimeout(function () { node.remove(); }, 250);
    }

    // -- banner ------------------------------------------------------------

    // Instagram's own palette, so the bar reads as part of the page.
    var CSS = [
        ":host{position:fixed;left:0;right:0;bottom:var(--lift,0px);z-index:2147483647;display:block;",
        "transform:translateY(110%);transition:transform .28s cubic-bezier(.32,.72,0,1);",
        "font-family:-apple-system,system-ui,sans-serif;color-scheme:light dark;",
        "--bg:#fff;--line:#eef0f2;--text:#0f1419;--muted:#636c76;--accent:#455efe}",
        "@media (prefers-color-scheme:dark){:host{",
        "--bg:#0d1014;--line:#363636;--text:#f4f7fb;--muted:#b1b9c2;--accent:#688eff}}",
        ":host(.shown){transform:translateY(0)}",
        ".bar{display:flex;align-items:center;gap:12px;box-sizing:border-box;",
        "padding:10px 12px calc(10px + env(safe-area-inset-bottom)) 12px;",
        "background:var(--bg);border-top:.5px solid var(--line)}",
        ":host(.lifted) .bar{padding-bottom:10px}",
        "img{width:38px;height:38px;border-radius:9px;flex:0 0 auto;display:block}",
        ".txt{flex:1 1 auto;min-width:0;line-height:1.25}",
        ".ttl{font-size:15px;font-weight:600;color:var(--text)}",
        ".sub{font-size:12px;color:var(--muted);overflow:hidden;",
        "text-overflow:ellipsis;white-space:nowrap;direction:ltr}",
        "button{font:inherit;border:0;cursor:pointer;-webkit-tap-highlight-color:transparent}",
        ".go{flex:0 0 auto;height:34px;padding:0 16px;border-radius:17px;",
        "background:var(--accent);color:#fff;font-size:14px;font-weight:600}",
        ".go:active{opacity:.6}",
        ".x{flex:0 0 auto;width:34px;height:34px;padding:0;background:transparent;",
        "color:var(--muted);font-size:22px;line-height:1}",
        "@media (prefers-reduced-motion:reduce){:host{transition:none}}"
    ].join("");

    function currentPath() {
        return window.location.hostname.replace(/^www\./, "") + window.location.pathname;
    }

    function attachStyles(root) {
        // A constructed sheet is not subject to the page's inline style policy.
        try {
            var sheet = new CSSStyleSheet();
            sheet.replaceSync(CSS);
            root.adoptedStyleSheets = [sheet];
            return;
        } catch (e) { /* older Safari */ }

        var style = document.createElement("style");
        style.textContent = CSS;
        root.appendChild(style);
    }

    function make(tag, className, content) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (content) node.textContent = content;
        return node;
    }

    function showBanner() {
        if (host || dismissed || !ready || !settings.banner || !isRedirectable() || !document.body) return;

        host = document.createElement("div");
        var root = host.attachShadow({ mode: "closed" });
        attachStyles(root);

        var icon = make("img");
        icon.src = ICON;
        icon.alt = "";

        var labels = make("div", "txt");
        labels.appendChild(make("div", "ttl", text("banner_title", "Open in Sparkle")));
        pathLabel = make("div", "sub", currentPath());
        labels.appendChild(pathLabel);

        var open = make("button", "go", text("banner_open", "Open"));
        open.addEventListener("click", function () { openInApp(true); });

        var close = make("button", "x", "✕");
        close.setAttribute("aria-label", text("banner_dismiss", "Stay in Safari"));
        close.addEventListener("click", dismiss);

        var bar = make("div", "bar");
        bar.appendChild(icon);
        bar.appendChild(labels);
        bar.appendChild(open);
        bar.appendChild(close);
        root.appendChild(bar);
        document.body.appendChild(host);
        placeBanner();
        // The page builds its own bars well after the banner is up.
        [300, 1000, 2500, 5000].forEach(function (delay) { setTimeout(placeBanner, delay); });

        requestAnimationFrame(function () {
            requestAnimationFrame(function () {
                if (host) host.classList.add("shown");
            });
        });
    }

    // Height of a bar the page itself pins to the bottom edge, such as the
    // site's tab bar, so the banner can sit on top of it instead of over it.
    function pageBarHeight() {
        var bottom = window.innerHeight;
        var nodes;
        try {
            nodes = document.elementsFromPoint(window.innerWidth / 2, bottom - 2);
        } catch (e) {
            return 0;
        }
        for (var i = 0; i < nodes.length; i++) {
            for (var el = nodes[i]; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
                if (el === host) break;
                var position = window.getComputedStyle(el).position;
                if (position !== "fixed" && position !== "sticky") continue;
                var rect = el.getBoundingClientRect();
                if (rect.height > 0 && rect.height <= 120 && Math.abs(rect.bottom - bottom) <= 2 &&
                    rect.width >= window.innerWidth * 0.9) {
                    return Math.round(rect.height);
                }
            }
        }
        return 0;
    }

    function placeBanner() {
        if (!host) return;
        var lift = pageBarHeight();
        host.style.setProperty("--lift", lift + "px");
        host.classList.toggle("lifted", lift > 0);
    }

    // Instagram moves between pages without loading a new document, and some of
    // those pages are web-only.
    function syncBanner() {
        if (host && !(settings.banner && isRedirectable())) {
            var node = host;
            host = null;
            pathLabel = null;
            node.remove();
        } else if (!host) {
            showBanner();
        } else if (pathLabel) {
            pathLabel.textContent = currentPath();
        }
        placeBanner();
    }

    // -- wiring ------------------------------------------------------------

    function onGesture(event) {
        // Taps inside the banner belong to its own buttons.
        if (host && event.target === host) return;
        openInApp(false, event);
        // The tap may have been an in-page link; catch up once it has settled.
        setTimeout(syncBanner, 400);
    }

    function onNavigated() {
        syncBanner();
        openInApp(false);
    }

    var listen = { capture: true, passive: true };

    // pointerup rather than pointerdown: a touch that turns into a scroll ends
    // in pointercancel, so scrolling never counts as a tap.
    window.addEventListener("pointerup", onGesture, listen);
    window.addEventListener("click", onGesture, listen);
    window.addEventListener("keydown", onGesture, listen);

    window.addEventListener("resize", placeBanner);
    window.addEventListener("popstate", onNavigated);
    window.addEventListener("hashchange", onNavigated);
    window.addEventListener("pageshow", onNavigated);

    // This runs at document_start, usually before <body> exists. Waiting for
    // it shows the banner well ahead of DOMContentLoaded on a page this heavy.
    function start() {
        ready = true;
        if (document.body) {
            showBanner();
        } else {
            var bodyWatch = new MutationObserver(function () {
                if (!document.body) return;
                bodyWatch.disconnect();
                showBanner();
            });
            bodyWatch.observe(document.documentElement, { childList: true });
        }
        openInApp(false, null, true);
    }

    function applySettings(stored) {
        if (!stored) return;
        if (typeof stored.banner === "boolean") settings.banner = stored.banner;
        if (typeof stored.auto === "boolean") settings.auto = stored.auto;
    }

    try {
        browser.storage.onChanged.addListener(function (changes) {
            if (changes.banner) settings.banner = changes.banner.newValue !== false;
            if (changes.auto) settings.auto = changes.auto.newValue !== false;
            if (ready) syncBanner();
        });

        browser.storage.local.get(["banner", "auto"]).then(function (stored) {
            applySettings(stored);
            start();
        }, start);
    } catch (e) {
        start();  // extension APIs unavailable: run with the defaults
    }
})();
