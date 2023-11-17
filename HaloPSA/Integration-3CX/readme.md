# 3CX Serverside CRM integration for HaloPSA
## Why do I need that?
HaloPSA does not offer a native, server-side integration for HaloPSA. They only offer a client-side integration where you can configure a URL in the 3CX client that opens up when you accept a call. When you configure a server-side integration, 3CX can lookup the numbers from incoming phone calls in HaloPSA and not only show your agents a name for the number, but also a button to open up the user in HaloPSA.

## Settings required in HaloPSA
No settings in HaloPSA are needed. You do need a readonly SQL account though and whitelist your 3CX IP. Contact Halo support for this.

## Settings in 3CX
1. Go to Settings -> CRM -> New -> Database MSSSQL
2. Specify database credentials. Halo uses a special port so you need to specify that in the "server"-field. Example: yournicedatabasehost.haloitsm.com,7001
3. Use the SQL statement from the file "3cx_phone_lookup" for the field "Lookup By Number SQL Statement". Replace +49 with your country code.
4. Use the SQL statement from the file "3cx_search_contacts" for the field "Search Contacts SQL Statement". Replace +49 with your country code.
5. Use this URL for the field "Contact URL prefix": https://yourhaloinstancefqdn/customers?mainview=user&hidegeneral=false&hideagents=false&hidedefaultsite=false&userid=
6. Leave all other fields empty
7. Click save

## Now what?
When a customer calls with a number that is assigned to a user in HaloPSA, 3CX will display their name and company. It will also provide a button to open the contact in HaloPSA.

## Caveats
Watch out if you modify the SQL. It appears that 3CX has a limit on how long those queries can be. 

## Further reading
If you need more info or you are a curoius person, check out 3CX official guide for databse CRM integrations: https://www.3cx.com/docs/sql-database-pbx-integration/.
Also, there's an official guide from Halo but they seem to be using yet another method for 3CX: https://halopsa.com/guides/article/?kbid=1254
