using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Music.Api.Services.Administration;

namespace Music.Api.Pages.Admin;

[AllowAnonymous]
public sealed class LoginModel(IAdminCredentialService credentials) : PageModel
{
    [BindProperty]
    [Required(ErrorMessage = "请输入管理员账号。")]
    [Display(Name = "管理员账号")]
    public string Username { get; set; } = string.Empty;

    [BindProperty]
    [Required(ErrorMessage = "请输入管理员密码。")]
    [DataType(DataType.Password)]
    [Display(Name = "管理员密码")]
    public string Password { get; set; } = string.Empty;

    [BindProperty]
    public string? ReturnUrl { get; set; }

    public bool IsConfigured => credentials.IsConfigured;

    public IActionResult OnGet(string? returnUrl = null)
    {
        if (User.Identity?.IsAuthenticated == true)
        {
            return RedirectToPage("/Admin/Scanning/Index");
        }

        ReturnUrl = Url.IsLocalUrl(returnUrl) ? returnUrl : null;
        return Page();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        if (!credentials.IsConfigured)
        {
            ModelState.AddModelError(string.Empty, "管理员账号尚未配置，请先完成后端配置。");
            return Page();
        }

        if (!ModelState.IsValid)
        {
            return Page();
        }

        if (!credentials.Validate(Username, Password))
        {
            ModelState.AddModelError(string.Empty, "管理员账号或密码不正确。");
            return Page();
        }

        var claims = new[]
        {
            new Claim(ClaimTypes.Name, credentials.Username),
            new Claim(ClaimTypes.Role, AdminAuthorization.RoleName)
        };
        var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        await HttpContext.SignInAsync(
            CookieAuthenticationDefaults.AuthenticationScheme,
            new ClaimsPrincipal(identity),
            new AuthenticationProperties
            {
                AllowRefresh = true,
                IsPersistent = false,
                ExpiresUtc = DateTimeOffset.UtcNow.AddHours(4)
            });

        return Url.IsLocalUrl(ReturnUrl)
            ? LocalRedirect(ReturnUrl!)
            : RedirectToPage("/Admin/Scanning/Index");
    }

    public async Task<IActionResult> OnPostLogoutAsync()
    {
        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        return RedirectToPage("/Admin/Login");
    }
}
